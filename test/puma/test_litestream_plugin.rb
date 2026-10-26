require "test_helper"
require "puma/plugin"
require_relative "../support/fake_litestream"

class TestLitestreamPlugin < ActiveSupport::TestCase
  include FakeLitestream

  class Events
    def initialize
      @hooks = Hash.new { |hash, key| hash[key] = [] }
    end

    %i[on_booted on_stopped on_restart].each do |hook|
      define_method(hook) { |&block| @hooks[hook] << block }
    end

    def fire(hook)
      @hooks[hook].each(&:call)
    end
  end

  class LogWriter
    attr_reader :messages

    def initialize
      @messages = []
    end

    def log(message)
      @messages << message
    end
  end

  Launcher = Struct.new(:events, :log_writer)

  def setup
    setup_fake_litestream
    @launcher = Launcher.new(Events.new, LogWriter.new)
    @plugin = Puma::Plugins.find("litestream").new
    # Puma runs these in threads of its own once every plugin has started.
    background = @background = []
    @plugin.define_singleton_method(:in_background) { |&block| background << Thread.new(&block) }
  end

  def teardown
    @launcher.events.fire(:on_stopped)
    @background.each(&:kill).each(&:join)
    release_lock
    teardown_fake_litestream
    # Leave a clean $? for the tests that read it after a stubbed command.
    system("true")
  end

  def test_stopping_puma_before_litestream_starts_does_not_raise
    @plugin.start(@launcher)

    @launcher.events.fire(:on_stopped)

    assert_empty log_lines
  end

  def test_waits_for_the_lock_without_holding_up_puma
    hold_lock
    _out, err = capture_io do
      with_fake_litestream do
        @plugin.start(@launcher)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @launcher.events.fire(:on_booted)
        assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5

        sleep 1
        assert_empty log_lines, "litestream should not start while another replicate holds the lock"

        release_lock
        assert wait_for { started_pids.size == 1 }, "litestream should start once the lock is free"
        @launcher.events.fire(:on_stopped)
      end
    end

    pid = started_pids.first
    assert_equal ["start #{pid}", "stop #{pid}"], log_lines
    assert_equal 1, err.scan("Waiting for #{@lock_path}").size
  end

  def test_stopping_puma_while_waiting_for_the_lock_never_starts_litestream
    hold_lock
    capture_io do
      with_fake_litestream do
        @plugin.start(@launcher)
        @launcher.events.fire(:on_booted)
        sleep 0.5

        @launcher.events.fire(:on_stopped)
        release_lock
        sleep 1
      end
    end

    assert_empty log_lines
    assert_nil @plugin.instance_variable_get(:@litestream_thread)
  end

  # Puma's stop runs in a signal handler on the main thread, so it can land
  # after the thread is created and before the plugin has recorded it.
  def test_a_stop_before_the_thread_is_recorded_leaves_no_litestream_running
    events = @launcher.events
    new_thread = Thread.method(:new)
    stop_after_create = proc do |*args, &block|
      new_thread.call(*args, &block).tap { events.fire(:on_stopped) }
    end

    capture_io do
      with_fake_litestream do
        @plugin.start(@launcher)
        Thread.stub(:new, stop_after_create) { events.fire(:on_booted) }
        sleep 1
      end
    end

    assert_equal started_pids.map { "stop #{_1}" }, log_lines.grep(/\Astop /)
    assert lock_free?
  end

  # Or after litestream is spawned and before its pid is recorded, where the
  # stop finds no pid to stop.
  def test_a_stop_before_the_pid_is_recorded_stops_litestream
    events = @launcher.events
    replicate = Litestream::Commands.method(:replicate)
    spawned = nil
    stop_after_spawn = proc do |**options|
      (spawned = replicate.call(**options)).tap { events.fire(:on_stopped) }
    end

    capture_io do
      with_fake_litestream do
        Litestream::Commands.stub(:replicate, stop_after_spawn) do
          @plugin.start(@launcher)
          events.fire(:on_booted)
          assert wait_for { spawned && !process_alive?(spawned) }, "litestream should be stopped"
        end
      end
    end

    assert lock_free?
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  # A phased restart or a fork_worker refork fires restart and then booted
  # again, with Puma serving throughout.
  def test_a_restart_and_boot_starts_litestream_again
    capture_io do
      with_fake_litestream do
        @plugin.start(@launcher)
        @launcher.events.fire(:on_booted)
        assert wait_for { started_pids.size == 1 }

        @launcher.events.fire(:on_restart)
        @launcher.events.fire(:on_booted)
        assert wait_for { started_pids.size == 2 }, "litestream should start again after a restart"
      end
    end

    first, second = started_pids
    assert_equal ["start #{first}", "stop #{first}", "start #{second}"], log_lines
  end

  def test_a_restart_while_waiting_for_the_lock_waits_again_after_boot
    hold_lock
    capture_io do
      with_fake_litestream do
        @plugin.start(@launcher)
        @launcher.events.fire(:on_booted)
        sleep 0.3

        @launcher.events.fire(:on_restart)
        @launcher.events.fire(:on_booted)
        sleep 0.3
        assert_empty log_lines

        release_lock
        assert wait_for { started_pids.size == 1 }
        sleep 0.6
      end
    end

    assert_equal ["start #{started_pids.first}"], log_lines
  end

  def test_still_stops_puma_when_litestream_dies_after_a_restart
    killed = []
    capture_io do
      with_fake_litestream do
        @plugin.start(@launcher)
        @launcher.events.fire(:on_booted)
        assert wait_for { started_pids.size == 1 }
        @launcher.events.fire(:on_restart)
        @launcher.events.fire(:on_booted)
        assert wait_for { started_pids.size == 2 }

        kill = Process.method(:kill)
        Process.stub :kill, proc { |signal, pid| (pid == Process.pid) ? killed << signal : kill.call(signal, pid) } do
          kill.call(:TERM, started_pids.last)
          assert wait_for(timeout: 6) { killed.any? }
        end
      end
    end

    assert_equal [:INT], killed
  end

  def stops_puma_when_litestream_cannot_be_started
    killed = []

    Process.stub :kill, proc { |signal, pid| killed << [signal, pid] } do
      @plugin.start(@launcher)
      @launcher.events.fire(:on_booted)
      assert wait_for { killed.any? }
    end

    assert_equal [[:INT, Process.pid]], killed
    assert_empty log_lines
    @launcher.log_writer.messages.join("\n")
  end

  def test_stops_puma_when_the_config_cannot_be_read
    File.write(@config, "dbs: [")

    message = with_fake_litestream { stops_puma_when_litestream_cannot_be_started }

    assert_match "Litestream failed to start", message
  end
end

require "puma/plugin"

# Started from Solid Queue's Puma plugin
# (https://github.com/rails/solid_queue/blob/15408647f1780033dad223d3198761ea2e1e983e/lib/puma/plugin/solid_queue.rb).
Puma::Plugin.create do
  attr_reader :litestream_pid, :log_writer

  def start(launcher)
    @log_writer = launcher.log_writer

    launcher.events.on_booted { start_litestream }
    launcher.events.on_stopped { stop_litestream(final: true) }
    launcher.events.on_restart { stop_litestream }
  end

  private

  # Replicate waits for the previous litestream on these databases to exit
  # (#84), which during a deploy is as long as the old container takes to
  # stop, so it runs in a thread of its own and never holds up Puma. That
  # thread then watches litestream. Puma fires booted again after every
  # phased restart or refork, each preceded by restart, which stops this
  # thread and litestream, so every boot starts a new one.
  #
  # Interrupts are deferred from the lock being taken to the pid being
  # recorded, and replicate allows them only while it waits. So when Puma
  # stops or restarts, the thread dies either before litestream exists or
  # after its pid is known, and stop_litestream stops whatever was started.
  # A stop can also land after the thread is created but before it is
  # recorded, when stop_litestream has no thread to stop: the thread records
  # the pid and then checks for that stop, and stop_litestream sets @stopped
  # before reading the pid, so one of the two stops litestream.
  def start_litestream
    return if @stopped || @litestream_thread&.alive?

    @litestream_thread = Thread.new do
      Puma.set_thread_name "litestream"
      Thread.handle_interrupt(Object => :never) do
        @litestream_pid = Litestream::Commands.replicate(async: true) unless @stopped
      end
      if @stopped
        stop_litestream_process
      else
        monitor_litestream
      end
    rescue => error
      log "Litestream failed to start, stopping Puma: #{error.message}"
      Process.kill(:INT, $$)
    end
  end

  # Puma calls this from a signal handler when it stops, where a thread can
  # be killed and joined but a mutex can't be taken. Puma fires the same
  # restart event for a hot restart and a phased restart or refork, so a
  # phased restart stops replication until its workers have booted again.
  def stop_litestream(final: false)
    @stopped = true if final
    thread, @litestream_thread = @litestream_thread, nil
    if thread && thread != Thread.current
      thread.kill
      thread.join
    end
    stop_litestream_process
  end

  def stop_litestream_process
    pid, @litestream_pid = litestream_pid, nil
    return unless pid

    Process.waitpid(pid, Process::WNOHANG)
    log_writer.log "Stopping Litestream..."
    Process.kill(:INT, pid)
    Process.wait(pid)
  rescue Errno::ECHILD, Errno::ESRCH
  end

  def monitor_litestream
    monitor(:litestream_dead?, "Detected Litestream has gone away, stopping Puma...")
  end

  def monitor(process_dead, message)
    loop do
      if send(process_dead)
        log message
        Process.kill(:INT, $$)
        break
      end
      sleep 2
    end
  end

  def litestream_dead?
    Process.waitpid(litestream_pid, Process::WNOHANG) if litestream_pid
    false
  rescue Errno::ECHILD, Errno::ESRCH
    true
  end

  def log(...)
    log_writer.log(...)
  end
end

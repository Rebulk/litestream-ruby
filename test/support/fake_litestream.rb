require "fileutils"
require "tmpdir"
require "yaml"

# A stand-in for `litestream replicate` that logs when it starts and stops and
# notices when a second one runs beside it, plus a config file naming one
# database for it to replicate.
module FakeLitestream
  def setup_fake_litestream
    @dir = Dir.mktmpdir
    @log = File.join(@dir, "log")
    @executable = File.join(@dir, "litestream")
    File.write(@executable, <<~SH)
      #!/bin/sh
      if ! mkdir "#{@log}.lock" 2>/dev/null; then echo overlap >> "#{@log}"; exit 42; fi
      echo "start $$" >> "#{@log}"
      trap 'echo "stop $$" >> "#{@log}"; rmdir "#{@log}.lock"; exit 0' TERM INT
      while true; do sleep 0.1; done
    SH
    File.chmod(0o755, @executable)

    @database = File.join(@dir, "storage", "production.sqlite3")
    FileUtils.mkdir_p(File.dirname(@database))
    @lock_path = File.join(@dir, "storage", ".production.sqlite3-litestream.lock")
    @config = File.join(@dir, "litestream.yml")
    File.write(@config, {"dbs" => [{"path" => @database, "replica" => {"type" => "file", "path" => File.join(@dir, "replica")}}]}.to_yaml)
    Litestream.config_path = @config
  end

  # Stops any fake that is still running, so a failed test leaves nothing behind.
  def teardown_fake_litestream
    started_pids.each do |pid|
      Process.kill(:TERM, pid) unless log_lines.include?("stop #{pid}")
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
    end
    Litestream.config_path = nil
    FileUtils.rm_rf(@dir)
  end

  def log_lines
    File.exist?(@log) ? File.readlines(@log, chomp: true) : []
  end

  def started_pids
    log_lines.grep(/\Astart /).map { _1.split.last.to_i }
  end

  # Whether another process could take the lock right now. flock locks belong
  # to the open file, so this conflicts with a lock held by this process too.
  def lock_free?
    File.open(@lock_path, File::RDONLY | File::CREAT) { _1.flock(File::LOCK_EX | File::LOCK_NB) } != false
  end

  def with_fake_litestream(&block)
    Litestream::Commands.stub(:executable, @executable, &block)
  end

  def hold_lock
    @held_lock = File.open(@lock_path, File::RDONLY | File::CREAT)
    @held_lock.flock(File::LOCK_EX)
  end

  def release_lock
    @held_lock&.close
  end

  def wait_for(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    true
  end
end

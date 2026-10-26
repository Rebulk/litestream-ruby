require "date"
require "fileutils"
require "json"
require "open3"
require "yaml"
require_relative "upstream"

module Litestream
  module Commands
    DEFAULT_DIR = File.expand_path(File.join(__dir__, "..", "..", "exe"))
    GEM_NAME = "litestream"

    # raised when the host platform is not supported by upstream litestream's binary releases
    UnsupportedPlatformException = Class.new(StandardError)

    # raised when the litestream executable could not be found where we expected it to be
    ExecutableNotFoundException = Class.new(StandardError)

    # raised when LITESTREAM_INSTALL_DIR does not exist
    DirectoryNotFoundException = Class.new(StandardError)

    # raised when a litestream command requires a database argument but it isn't provided
    DatabaseRequiredException = Class.new(StandardError)

    # raised when a litestream command fails
    CommandFailedException = Class.new(StandardError)

    # raised when a litestream command times out
    CommandTimeoutException = Class.new(CommandFailedException)

    module Output
      class << self
        def format(data)
          return "" if data.nil? || data.empty?

          headers = data.first.keys.map(&:to_s)
          widths = headers.map.with_index { |h, i|
            [h.length, data.map { |r| r[data.first.keys[i]].to_s.length }.max].max
          }

          format_str = widths.map { |w| "%-#{w}s" }.join("  ")
          ([headers] + data.map(&:values)).map { |row|
            sprintf(format_str, *row.map(&:to_s))
          }.join("\n")
        end
      end
    end

    class << self
      def platform
        [:cpu, :os].map { |m| Gem::Platform.local.send(m) }.join("-")
      end

      def executable(exe_path: DEFAULT_DIR)
        litestream_install_dir = ENV["LITESTREAM_INSTALL_DIR"]
        if litestream_install_dir
          if File.directory?(litestream_install_dir)
            unless @litestream_install_dir_noted
              warn "NOTE: using LITESTREAM_INSTALL_DIR to find litestream executable: #{litestream_install_dir}"
              @litestream_install_dir_noted = true
            end
            exe_path = litestream_install_dir
            exe_file = File.expand_path(File.join(litestream_install_dir, "litestream"))
          else
            raise DirectoryNotFoundException, <<~MESSAGE
              LITESTREAM_INSTALL_DIR is set to #{litestream_install_dir}, but that directory does not exist.
            MESSAGE
          end
        else
          if Litestream::Upstream::NATIVE_PLATFORMS.keys.none? { |p| Gem::Platform.match_gem?(Gem::Platform.new(p), GEM_NAME) }
            raise UnsupportedPlatformException, <<~MESSAGE
              litestream-ruby does not support the #{platform} platform
              Please install litestream following instructions at https://litestream.io/install
            MESSAGE
          end

          exe_file = Dir.glob(File.expand_path(File.join(exe_path, "*", "litestream"))).find do |f|
            Gem::Platform.match_gem?(Gem::Platform.new(File.basename(File.dirname(f))), GEM_NAME)
          end
        end

        if exe_file.nil? || !File.exist?(exe_file)
          raise ExecutableNotFoundException, <<~MESSAGE
            Cannot find the litestream executable for #{platform} in #{exe_path}

            If you're using bundler, please make sure you're on the latest bundler version:

                gem install bundler
                bundle update --bundler

            Then make sure your lock file includes this platform by running:

                bundle lock --add-platform #{platform}
                bundle install

            See `bundle lock --help` output for details.

            If you're still seeing this message after taking those steps, try running
            `bundle config` and ensure `force_ruby_platform` isn't set to `true`. See
            https://github.com/fractaledmind/litestream-ruby#check-bundle_force_ruby_platform
            for more details.
          MESSAGE
        end

        exe_file
      end

      # Replicate runs either as a child process or in the foreground, depending on the context.
      # The Puma plugin starts it as a child and gets its pid back; the rake task runs it in the
      # foreground and streams its output.
      def replicate(async: false, **argv)
        cmd = prepare("replicate", argv)
        run_replicate(cmd, async: async)
      rescue CommandFailedException
        raise
      rescue
        raise CommandFailedException, "Failed to execute `#{cmd.join(" ")}`"
      end

      def restore(database, **argv)
        raise DatabaseRequiredException, "database argument is required for restore command, e.g. litestream:restore -- --database=path/to/database.sqlite" if database.nil?

        execute("restore", argv, database, tabled_output: false)
      end

      def databases(**argv)
        execute("databases", argv)
      end

      def ltx(database, **argv)
        raise DatabaseRequiredException, "database argument is required for ltx command, e.g. litestream:ltx -- --database=path/to/database.sqlite" if database.nil?

        execute("ltx", argv, database)
      end

      # Litestream 0.5 filters `status` by the absolute database path, while
      # `ltx` and `restore` match the path as written in the config file, so a
      # relative path is expanded here to keep the documented
      # `--database=storage/production.sqlite3` form working.
      def status(database = nil, **argv)
        execute("status", argv, database && File.expand_path(database))
      end

      def generations(*)
        raise CommandFailedException, "`generations` was removed in Litestream 0.5; use `ltx` (see README, Upgrading from 0.3)"
      end

      def snapshots(*)
        raise CommandFailedException, "`snapshots` was removed in Litestream 0.5; use `ltx` (see README, Upgrading from 0.3)"
      end

      def wal(*)
        raise CommandFailedException, "`wal` was removed in Litestream 0.5; use `ltx` (see README, Upgrading from 0.3)"
      end

      private

      def execute(command, argv = {}, database = nil, tabled_output: true)
        argv = argv.stringify_keys
        timeout = argv.delete("timeout")
        output = if argv.delete("json")
          argv["-json"] = nil
          :json
        elsif tabled_output
          :table
        else
          :raw
        end

        cmd = prepare(command, argv, database)
        run(cmd, output: output, timeout: timeout)
      end

      def prepare(command, argv = {}, database = nil)
        ENV["LITESTREAM_REPLICA_BUCKET"] ||= Litestream.replica_bucket
        ENV["LITESTREAM_REPLICA_REGION"] ||= Litestream.replica_region
        ENV["LITESTREAM_REPLICA_ENDPOINT"] ||= Litestream.replica_endpoint
        ENV["LITESTREAM_ACCESS_KEY_ID"] ||= Litestream.replica_key_id
        ENV["LITESTREAM_SECRET_ACCESS_KEY"] ||= Litestream.replica_access_key

        args = {
          "--config" => Litestream.config_path.to_s
        }.merge(argv.stringify_keys).to_a.flatten.compact.map(&:to_s)
        cmd = [executable, command, *args, database].compact.map(&:to_s)
        puts cmd.inspect if ENV["DEBUG"]

        cmd
      end

      # Runs the command without a shell and returns its parsed stdout. A non-zero
      # exit raises with stderr. With a timeout, the command runs in its own
      # process group and is killed (TERM, then KILL) when the deadline passes.
      def run(cmd, output:, timeout: nil)
        stdin, stdout, stderr, wait_thread = Open3.popen3(*cmd, pgroup: true)
        stdin.close
        stdout_reader = Thread.new { stdout.read }
        stderr_reader = Thread.new { stderr.read }

        # The readers finish when the last process holding the pipes exits, so
        # waiting on them covers descendants the direct child may have left behind.
        unless wait_thread.join(timeout) && stdout_reader.join(timeout) && stderr_reader.join(timeout)
          kill_process_group("TERM", wait_thread.pid)
          wait_thread.join(1)
          kill_process_group("KILL", wait_thread.pid)
          wait_thread.join
          [stdout_reader, stderr_reader].each(&:join)
          raise CommandTimeoutException, "Failed to execute `#{cmd[1]}`: timed out after #{timeout} seconds"
        end

        status = wait_thread.value
        unless status.success?
          raise CommandFailedException, "Failed to execute `#{cmd[1]}` (exit status #{status.exitstatus}): #{stderr_reader.value.strip[0, 500]}"
        end

        case output
        when :json then parse_json(cmd, stdout_reader.value)
        when :table then parse_table(stdout_reader.value)
        else stdout_reader.value
        end
      ensure
        [stdout_reader, stderr_reader].each { |reader| reader&.join }
        [stdin, stdout, stderr].each { |io| io&.close unless io&.closed? }
      end

      # macOS answers EPERM rather than ESRCH when every process left in the
      # group has exited but not yet been reaped.
      def kill_process_group(signal, pid)
        Process.kill(signal, -pid)
      rescue Errno::ESRCH, Errno::EPERM
      end

      # Two opt-in restore skips (-if-db-not-exists when the output exists,
      # -if-replica-exists with no backups) exit 0 and print one logfmt line on
      # stdout instead of JSON. They come back as {"skipped" => true, "message" => ...}.
      def parse_json(cmd, stdout)
        stdout = stdout.strip
        return if stdout.empty?
        return JSON.parse(stdout) if stdout.start_with?("{", "[")

        skipped = stdout.match(/\Atime=\S+ level=\S+ msg=(?:"([^"]*)"|(\S+))/)
        return {"skipped" => true, "message" => skipped[1] || skipped[2]} if skipped

        raise CommandFailedException, "Unexpected output from `#{cmd[1]}`: #{stdout.lines.first.to_s.strip[0, 200]}"
      end

      # Litestream pads columns with at least two spaces, and some headers and
      # values hold a single one ("local txid", "231 kB", "no database").
      def parse_table(stdout)
        keys, *rows = stdout.strip.split("\n").map { _1.strip.split(/\s{2,}/) }
        return [] unless keys

        rows.map { keys.zip(_1).to_h }
      end

      # Async replication returns the pid of the litestream process itself so a
      # supervisor can signal and wait on it. Process.spawn is fork-and-exec in
      # one call, so the pid it returns is the one that becomes litestream. The
      # previous `exec(*cmd) if fork.nil?` also execs in a child but returns
      # into the parent too, and the Puma plugin wrapped that in a fork of its
      # own, so it recorded a pid that exited immediately while the daemon was
      # reparented to init and outlived Puma.
      #
      # Litestream 0.5.17 takes no lock on the database it replicates, and two
      # replicate processes on one database can upload a corrupt LTX file that
      # stalls compaction for good (#84). A deploy that starts the new container
      # before stopping the old one runs exactly that, so replicate first waits
      # for an exclusive lock for each database. The lock files are handed to
      # the litestream process and closed here, so litestream holds them: one
      # that outlives a SIGKILLed Puma or rake still keeps the next one out.
      # With -exec, the command litestream starts inherits them as well (Go
      # passes on every descriptor it was given), so the lock is free once both
      # have exited. Holding it here instead would not end it sooner: the rake
      # task reads litestream's output until that command closes it too.
      def run_replicate(cmd, async:)
        locks = lock_databases(lock_paths(cmd))
        redirects = locks.to_h { [_1, _1] }

        if async
          pid = Process.spawn(*cmd, **redirects)
          locks.each(&:close)
          pid
        else
          # When running in-process, we capture output continuously and write to stdout.
          IO.popen(cmd, err: [:child, :out], **redirects) do |io|
            locks.each(&:close)
            io.each_line { |line| puts line }
          end
          status = $?
          # `replicate` runs until it is signalled, so a signal is how it is
          # meant to end. A non-zero exit is litestream failing to start or
          # dying on its own, which is invisible today: the task exits 0 and a
          # supervisor sees a clean stop rather than a crash to restart.
          if status && !status.success? && !status.signaled?
            raise CommandFailedException, "Failed to execute `replicate` (exit status #{status.exitstatus})"
          end
        end
      ensure
        locks&.each { _1.close unless _1.closed? }
      end

      # One lock file per database in the config file the command names, kept
      # where Litestream keeps that database's state, so it is on the volume
      # the containers share: `.<db>-litestream.lock` beside the database's
      # `.<db>-litestream` directory, or beside its `meta-path:`. A `dir:` entry
      # gets one `.litestream.lock` inside the directory (or its `meta-dir:` or
      # `meta-path:`), which Litestream does not take for a database because it
      # is not one. `litestream databases` would be the obvious source, but
      # 0.5.17 reports a `dir:` entry as the working directory and refuses one
      # that sets `meta-dir:`.
      #
      # Paths are read the way Litestream reads them: environment variables
      # expanded unless -no-expand-env, relative paths from the working
      # directory. Litestream's `$PID` and `$$` are left alone, and `~user` is
      # expanded, neither of which a database path has a use for. An entry that
      # Litestream would refuse is skipped, and Litestream exits with the error.
      def lock_paths(cmd)
        config_path = nil
        expand_env = true
        args = cmd.drop(2)
        args.each_with_index do |arg, index|
          case arg
          when "-config", "--config" then config_path = args[index + 1]
          when /\A--?config=(.*)\z/ then config_path = $1
          when "-no-expand-env", "--no-expand-env" then expand_env = false
          end
        end
        return [] unless config_path && File.file?(config_path)

        yaml = File.read(config_path)
        yaml = yaml.gsub(/\$(?:\{(\w+)\}|(\w+))/) { ENV.fetch($1 || $2, "") } if expand_env
        # Safe loading is enough for the few keys read here, and environment
        # values are spliced into the text before it is parsed, so this must not
        # build arbitrary objects. Go's YAML reads `:debug` and dates as strings;
        # Psych needs them permitted.
        config = YAML.safe_load(yaml, aliases: true, permitted_classes: [Date, Time, Symbol])
        dbs = config.is_a?(Hash) ? config["dbs"] : nil
        return [] unless dbs.is_a?(Array)

        dbs.grep(Hash).filter_map do |db|
          if db["dir"]
            File.join(expand_path(db["meta-dir"] || db["meta-path"] || db["dir"]), ".litestream.lock")
          elsif db["path"]
            path = expand_path(db["path"])
            meta_path = db["meta-path"] ? expand_path(db["meta-path"]) : File.join(File.dirname(path), ".#{File.basename(path)}-litestream")
            "#{meta_path}.lock"
          end
        end
      rescue Psych::Exception => error
        raise CommandFailedException, "Failed to read #{config_path} to lock its databases: #{error.message}"
      end

      def expand_path(path)
        File.expand_path(path.to_s.sub(%r{\Asqlite3?://}, ""))
      end

      LOCK_RETRY_INTERVAL = 0.5

      # Takes every lock or none: while another replicate holds one, all are
      # closed and tried again shortly. So two waiters can't each hold a lock
      # the other needs, and nothing is held open while waiting, which Puma
      # would otherwise pass to every worker it forks meanwhile, and a worker
      # would then hold the lock after litestream exits. That leaves only the
      # moment from taking the locks to closing them after the spawn, about a
      # millisecond: a worker forked then inherits them and holds them until it
      # exits (in a test, 30 of 4,153 forks did). Under fork_worker a worker 0
      # forked then keeps them across later reforks, so the litestream started
      # after a refork waits until that worker exits.
      #
      # The files are opened read-only and created 0644, so containers sharing
      # a uid, as containers of one image do, can open one another's. The wait
      # stays interruptible where the caller defers interrupts: the Puma plugin
      # does, so that stopping Puma either finds the litestream it started or
      # keeps it from starting.
      def lock_databases(lock_paths)
        lock_paths = lock_paths.uniq.sort
        waited = false
        loop do
          locks = []
          acquired = false
          begin
            busy = lock_paths.find do |lock_path|
              FileUtils.mkdir_p(File.dirname(lock_path))
              locks << (lock = File.open(lock_path, File::RDONLY | File::CREAT, 0o644))
              !lock.flock(File::LOCK_EX | File::LOCK_NB)
            rescue SystemCallError => error
              raise CommandFailedException, "Failed to lock #{lock_path} before replicating: #{error.message}"
            end
            unless busy
              warn "Locked #{lock_paths.join(", ")}, starting `litestream replicate`" if waited
              acquired = true
              return locks
            end
          ensure
            locks.each(&:close) unless acquired
          end

          warn "Waiting for #{busy}: another `litestream replicate` holds it" unless waited
          waited = true
          Thread.handle_interrupt(Object => :immediate) { sleep LOCK_RETRY_INTERVAL }
        end
      end
    end
  end
end

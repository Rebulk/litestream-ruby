require "test_helper"

class TestCommands < ActiveSupport::TestCase
  def run
    result = nil
    Litestream::Commands.stub :fork, nil do
      Litestream::Commands.stub :executable, "exe/test/litestream" do
        capture_io { result = super }
      end
    end
    result
  end

  def teardown
    Litestream.replica_bucket = ENV["LITESTREAM_REPLICA_BUCKET"] = nil
    Litestream.replica_key_id = ENV["LITESTREAM_ACCESS_KEY_ID"] = nil
    Litestream.replica_access_key = ENV["LITESTREAM_SECRET_ACCESS_KEY"] = nil
    Litestream.config_path = nil
  end

  class TestReplicateCommand < TestCommands
    def test_replicate_with_no_options
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "replicate", command
        assert_equal 2, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
      end
      Litestream::Commands.stub :run_replicate, stub do
        Litestream::Commands.replicate
      end
    end

    def test_replicate_with_boolean_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "replicate", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--no-expand-env", argv[2]
      end
      Litestream::Commands.stub :run_replicate, stub do
        Litestream::Commands.replicate("--no-expand-env" => nil)
      end
    end

    def test_replicate_with_string_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "replicate", command
        assert_equal 4, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--exec", argv[2]
        assert_equal "command", argv[3]
      end
      Litestream::Commands.stub :run_replicate, stub do
        Litestream::Commands.replicate("--exec" => "command")
      end
    end

    def test_replicate_with_symbol_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "replicate", command
        assert_equal 4, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--exec", argv[2]
        assert_equal "command", argv[3]
      end
      Litestream::Commands.stub :run_replicate, stub do
        Litestream::Commands.replicate("--exec": "command")
      end
    end

    def test_replicate_with_config_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "replicate", command
        assert_equal 2, argv.size
        assert_equal "--config", argv[0]
        assert_equal "CONFIG", argv[1]
      end
      Litestream::Commands.stub :run_replicate, stub do
        Litestream::Commands.replicate("--config" => "CONFIG")
      end
    end

    def test_replicate_sets_replica_bucket_env_var_from_config_when_env_var_not_set
      Litestream.replica_bucket = "mybkt"

      Litestream::Commands.stub :run_replicate, nil do
        Litestream::Commands.replicate
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_replicate_sets_replica_key_id_env_var_from_config_when_env_var_not_set
      Litestream.replica_key_id = "mykey"

      Litestream::Commands.stub :run_replicate, nil do
        Litestream::Commands.replicate
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_replicate_sets_replica_access_key_env_var_from_config_when_env_var_not_set
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run_replicate, nil do
        Litestream::Commands.replicate
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_replicate_sets_all_env_vars_from_config_when_env_vars_not_set
      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run_replicate, nil do
        Litestream::Commands.replicate
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_replicate_does_not_set_env_var_from_config_when_env_vars_already_set
      ENV["LITESTREAM_REPLICA_BUCKET"] = "original_bkt"
      ENV["LITESTREAM_ACCESS_KEY_ID"] = "original_key"
      ENV["LITESTREAM_SECRET_ACCESS_KEY"] = "original_access"

      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run_replicate, nil do
        Litestream::Commands.replicate
      end

      assert_equal "original_bkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "original_key", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "original_access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end
  end

  class TestRestoreCommand < TestCommands
    def test_restore_with_no_options
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "restore", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "db/test.sqlite3", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.restore("db/test.sqlite3")
      end
    end

    def test_restore_with_boolean_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "restore", command
        assert_equal 4, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--if-db-not-exists", argv[2]
        assert_equal "db/test.sqlite3", argv[3]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.restore("db/test.sqlite3", "--if-db-not-exists" => nil)
      end
    end

    def test_restore_with_string_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "restore", command
        assert_equal 5, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--parallelism", argv[2]
        assert_equal 10, argv[3]
        assert_equal "db/test.sqlite3", argv[4]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.restore("db/test.sqlite3", "--parallelism" => 10)
      end
    end

    def test_restore_with_config_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "restore", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_equal "CONFIG", argv[1]
        assert_equal "db/test.sqlite3", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.restore("db/test.sqlite3", "--config" => "CONFIG")
      end
    end

    def test_restore_sets_replica_bucket_env_var_from_config_when_env_var_not_set
      Litestream.replica_bucket = "mybkt"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.restore("db/test.sqlite3")
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_restore_sets_replica_key_id_env_var_from_config_when_env_var_not_set
      Litestream.replica_key_id = "mykey"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.restore("db/test.sqlite3")
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_restore_sets_replica_access_key_env_var_from_config_when_env_var_not_set
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.restore("db/test.sqlite3")
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_restore_sets_all_env_vars_from_config_when_env_vars_not_set
      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.restore("db/test.sqlite3")
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_restore_does_not_set_env_var_from_config_when_env_vars_already_set
      ENV["LITESTREAM_REPLICA_BUCKET"] = "original_bkt"
      ENV["LITESTREAM_ACCESS_KEY_ID"] = "original_key"
      ENV["LITESTREAM_SECRET_ACCESS_KEY"] = "original_access"

      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.restore("db/test.sqlite3")
      end

      assert_equal "original_bkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "original_key", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "original_access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end
  end

  class TestDatabasesCommand < TestCommands
    def test_databases_with_no_options
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "databases", command
        assert_equal 2, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.databases
      end
    end

    def test_databases_with_boolean_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "databases", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--no-expand-env", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.databases("--no-expand-env" => nil)
      end
    end

    def test_databases_with_string_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "databases", command
        assert_equal 4, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--exec", argv[2]
        assert_equal "command", argv[3]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.databases("--exec" => "command")
      end
    end

    def test_databases_with_config_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "databases", command
        assert_equal 2, argv.size
        assert_equal "--config", argv[0]
        assert_equal "CONFIG", argv[1]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.databases("--config" => "CONFIG")
      end
    end

    def test_databases_sets_replica_bucket_env_var_from_config_when_env_var_not_set
      Litestream.replica_bucket = "mybkt"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.databases
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_databases_sets_replica_key_id_env_var_from_config_when_env_var_not_set
      Litestream.replica_key_id = "mykey"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.databases
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_databases_sets_replica_access_key_env_var_from_config_when_env_var_not_set
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.databases
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_databases_sets_all_env_vars_from_config_when_env_vars_not_set
      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.databases
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_databases_does_not_set_env_var_from_config_when_env_vars_already_set
      ENV["LITESTREAM_REPLICA_BUCKET"] = "original_bkt"
      ENV["LITESTREAM_ACCESS_KEY_ID"] = "original_key"
      ENV["LITESTREAM_SECRET_ACCESS_KEY"] = "original_access"

      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.databases
      end

      assert_equal "original_bkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "original_key", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "original_access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_databases_read_from_custom_configured_litestream_config_path
      Litestream.config_path = "dummy/config/litestream/production.yml"

      stub = proc do |cmd, _async|
        _executable, _command, *argv = cmd

        assert_equal 2, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream/production.yml"), argv[1]
      end

      Litestream::Commands.stub :run, stub do
        Litestream::Commands.databases
      end
    end
  end

  class TestLtxCommand < TestCommands
    def test_ltx_with_no_options
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "ltx", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "db/test.sqlite3", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.ltx("db/test.sqlite3")
      end
    end

    def test_ltx_with_boolean_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "ltx", command
        assert_equal 4, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--level", argv[2]
        assert_equal "db/test.sqlite3", argv[3]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.ltx("db/test.sqlite3", "--level" => nil)
      end
    end

    def test_ltx_with_string_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "ltx", command
        assert_equal 5, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--level", argv[2]
        assert_equal "all", argv[3]
        assert_equal "db/test.sqlite3", argv[4]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.ltx("db/test.sqlite3", "--level" => "all")
      end
    end

    def test_ltx_with_config_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "ltx", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_equal "CONFIG", argv[1]
        assert_equal "db/test.sqlite3", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.ltx("db/test.sqlite3", "--config" => "CONFIG")
      end
    end

    def test_ltx_requires_database
      error = assert_raises Litestream::Commands::DatabaseRequiredException do
        Litestream::Commands.ltx(nil)
      end
      assert_match "database argument is required for ltx command", error.message
    end

    def test_ltx_sets_replica_bucket_env_var_from_config_when_env_var_not_set
      Litestream.replica_bucket = "mybkt"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.ltx("db/test.sqlite3")
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_ltx_sets_replica_key_id_env_var_from_config_when_env_var_not_set
      Litestream.replica_key_id = "mykey"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.ltx("db/test.sqlite3")
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_ltx_sets_replica_access_key_env_var_from_config_when_env_var_not_set
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.ltx("db/test.sqlite3")
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_ltx_sets_all_env_vars_from_config_when_env_vars_not_set
      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.ltx("db/test.sqlite3")
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_ltx_does_not_set_env_var_from_config_when_env_vars_already_set
      ENV["LITESTREAM_REPLICA_BUCKET"] = "original_bkt"
      ENV["LITESTREAM_ACCESS_KEY_ID"] = "original_key"
      ENV["LITESTREAM_SECRET_ACCESS_KEY"] = "original_access"

      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.ltx("db/test.sqlite3")
      end

      assert_equal "original_bkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "original_key", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "original_access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_json_convenience_adds_json_flag
      stub = proc do |cmd|
        assert_includes cmd, "-json"
        refute_includes cmd, "json"
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.ltx("db/test.sqlite3", json: true)
      end
    end

    def test_run_parses_json_output
      stdout = '[{"level":0,"min_txid":"0000000000000001"}]'
      Litestream::Commands.stub :`, stdout do
        result = Litestream::Commands.send(:run, ["litestream", "ltx", "-json"], tabled_output: true)
        assert_equal [{"level" => 0, "min_txid" => "0000000000000001"}], result
      end
    end

    def test_run_parses_json_output_with_double_dash_flag
      stdout = '[{"level":9,"max_txid":"000000000000000a"}]'
      Litestream::Commands.stub :`, stdout do
        result = Litestream::Commands.send(:run, ["litestream", "ltx", "--json"], tabled_output: true)
        assert_equal 9, result.first["level"]
      end
    end

    def test_json_false_does_not_add_json_flag
      stub = proc do |cmd|
        refute_includes cmd, "-json"
        refute_includes cmd, "--json"
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.ltx("db/test.sqlite3", json: false)
      end
    end
  end

  class TestStatusCommand < TestCommands
    def test_status_with_no_database
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "status", command
        assert_equal 2, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status
      end
    end

    def test_status_with_database
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "status", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "db/test.sqlite3", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status("db/test.sqlite3")
      end
    end

    def test_status_with_boolean_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "status", command
        assert_equal 4, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--no-expand-env", argv[2]
        assert_equal "db/test.sqlite3", argv[3]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status("db/test.sqlite3", "--no-expand-env" => nil)
      end
    end

    def test_status_with_string_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "status", command
        assert_equal 5, argv.size
        assert_equal "--config", argv[0]
        assert_match Regexp.new("dummy/config/litestream.yml"), argv[1]
        assert_equal "--log-level", argv[2]
        assert_equal "debug", argv[3]
        assert_equal "db/test.sqlite3", argv[4]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status("db/test.sqlite3", "--log-level" => "debug")
      end
    end

    def test_status_with_config_option
      stub = proc do |cmd|
        executable, command, *argv = cmd
        assert_match Regexp.new("exe/test/litestream"), executable
        assert_equal "status", command
        assert_equal 3, argv.size
        assert_equal "--config", argv[0]
        assert_equal "CONFIG", argv[1]
        assert_equal "db/test.sqlite3", argv[2]
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status("db/test.sqlite3", "--config" => "CONFIG")
      end
    end

    def test_status_sets_replica_bucket_env_var_from_config_when_env_var_not_set
      Litestream.replica_bucket = "mybkt"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.status("db/test.sqlite3")
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_status_sets_replica_key_id_env_var_from_config_when_env_var_not_set
      Litestream.replica_key_id = "mykey"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.status("db/test.sqlite3")
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_nil ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_status_sets_replica_access_key_env_var_from_config_when_env_var_not_set
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.status("db/test.sqlite3")
      end

      assert_nil ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_nil ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_status_sets_all_env_vars_from_config_when_env_vars_not_set
      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.status("db/test.sqlite3")
      end

      assert_equal "mybkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "mykey", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_status_does_not_set_env_var_from_config_when_env_vars_already_set
      ENV["LITESTREAM_REPLICA_BUCKET"] = "original_bkt"
      ENV["LITESTREAM_ACCESS_KEY_ID"] = "original_key"
      ENV["LITESTREAM_SECRET_ACCESS_KEY"] = "original_access"

      Litestream.replica_bucket = "mybkt"
      Litestream.replica_key_id = "mykey"
      Litestream.replica_access_key = "access"

      Litestream::Commands.stub :run, nil do
        Litestream::Commands.status("db/test.sqlite3")
      end

      assert_equal "original_bkt", ENV["LITESTREAM_REPLICA_BUCKET"]
      assert_equal "original_key", ENV["LITESTREAM_ACCESS_KEY_ID"]
      assert_equal "original_access", ENV["LITESTREAM_SECRET_ACCESS_KEY"]
    end

    def test_status_json_convenience_adds_json_flag
      stub = proc do |cmd|
        assert_includes cmd, "-json"
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status(json: true)
      end
    end

    def test_run_parses_json_hash_output
      stdout = '{"db_path":"db/test.sqlite3","txid":"000000000000000a"}'
      Litestream::Commands.stub :`, stdout do
        result = Litestream::Commands.send(:run, ["litestream", "restore", "-json"], tabled_output: false)
        assert_equal "000000000000000a", result["txid"]
      end
    end

    def test_status_all_databases_with_json
      stub = proc do |cmd|
        assert_equal "status", cmd[1]
        assert_equal "-json", cmd.last
      end
      Litestream::Commands.stub :run, stub do
        Litestream::Commands.status(json: true)
      end
    end
  end

  class TestOutput < ActiveSupport::TestCase
    def test_output_formatting_generates_table_with_data
      data = [
        {"path" => "/storage/database.db", "replica" => "s3"},
        {"path" => "/storage/another-database.db", "replica" => "s3"}
      ]

      result = Litestream::Commands::Output.format(data)
      lines = result.split("\n")

      assert_equal 3, lines.length

      assert_includes lines[0], "path"
      assert_includes lines[0], "replica"
      assert_includes lines[1], "/storage/database.db"
      assert_includes lines[2], "/storage/another-database.db"
    end

    def test_output_formatting_generates_formatted_table
      data = [
        {path: "/storage/database.db", replica: "s3"},
        {path: "/storage/another-database.db", replica: "s3"}
      ]

      result = Litestream::Commands::Output.format(data)
      lines = result.split("\n")

      replica_pos = lines[0].index("replica")
      assert_equal replica_pos, lines[1].index("s3")
      assert_equal replica_pos, lines[2].index("s3")
    end
  end
end

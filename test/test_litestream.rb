# frozen_string_literal: true

require "test_helper"

class TestLitestream < Minitest::Test
  def teardown
    Litestream.systemctl_command = nil
  end

  def test_that_it_has_a_version_number
    refute_nil ::Litestream::VERSION
  end

  def test_replicate_process_systemd
    stubbed_status = ["● litestream.service - Litestream",
      "     Loaded: loaded (/lib/systemd/system/litestream.service; enabled; vendor preset: enabled)",
      "     Active: active (running) since Tue 2023-07-25 13:49:43 UTC; 8 months 24 days ago",
      "   Main PID: 1179656 (litestream)",
      "      Tasks: 9 (limit: 1115)",
      "     Memory: 22.9M",
      "        CPU: 10h 49.843s",
      "     CGroup: /system.slice/litestream.service",
      "             └─1179656 /usr/bin/litestream replicate",
      "",
      "Warning: some journal files were not opened due to insufficient permissions."].join("\n")
    system("true")
    Litestream.stub :`, stubbed_status do
      info = Litestream.replicate_process

      assert_equal info[:status], "running"
      assert_equal info[:pid], "1179656"
      assert_equal info[:started].class, DateTime
    end
  end

  def test_replicate_process_systemd_custom_command
    stubbed_status = ["● myapp-litestream.service - Litestream",
      "     Loaded: loaded (/lib/systemd/system/litestream.service; enabled; vendor preset: enabled)",
      "     Active: active (running) since Tue 2023-07-25 13:49:43 UTC; 8 months 24 days ago",
      "   Main PID: 1179656 (litestream)",
      "      Tasks: 9 (limit: 1115)",
      "     Memory: 22.9M",
      "        CPU: 10h 49.843s",
      "     CGroup: /system.slice/litestream.service",
      "             └─1179656 /usr/bin/litestream replicate",
      "",
      "Warning: some journal files were not opened due to insufficient permissions."].join("\n")
    Litestream.systemctl_command = "systemctl --user status myapp-litestream.service"

    system("true")
    Litestream.stub :`, stubbed_status do
      info = Litestream.replicate_process

      assert_equal info[:status], "running"
      assert_equal info[:pid], "1179656"
      assert_equal info[:started].class, DateTime
    end
  end

  def test_replicate_process_ps
    stubbed_ps_list = [
      "40358 ttys008    0:01.11 ruby --yjit bin/rails litestream:replicate",
      "40364 ttys008    0:00.07 /path/to/litestream-ruby/exe/architecture/litestream replicate --config /path/to/app/config/litestream.yml"
    ].join("\n")

    stubbed_ps_status = [
      "STAT STARTED",
      "S+   Mon Jul  1 11:10:58 2024"
    ].join("\n")

    stubbed_backticks = proc do |arg|
      case arg
      when "ps -ax | grep litestream | grep replicate"
        stubbed_ps_list
      when %(ps -o "state,lstart" 40364)
        stubbed_ps_status
      else
        ""
      end
    end

    system("true")
    Litestream.stub :`, stubbed_backticks do
      info = Litestream.replicate_process

      assert_equal info[:status], "sleeping"
      assert_equal info[:pid], "40364"
      assert_equal info[:started].class, DateTime
    end
  end

  def test_databases_derives_replication_summary_and_isolates_errors
    database_path = Rails.root.join("storage/test.sqlite3").to_s
    failing_path = Rails.root.join("storage/failing.sqlite3").to_s
    databases = [
      {"path" => database_path, "replica" => "file"},
      {"path" => failing_path, "replica" => "file"}
    ]
    status = [{"database" => database_path, "status" => "ok", "local_txid" => "000000000000000a", "wal_size" => "128 kB"}]
    ltx = [
      {"level" => 0, "min_txid" => "0000000000000008", "max_txid" => "0000000000000008", "size" => 100, "timestamp" => "2026-09-08T01:00:00Z"},
      {"level" => 0, "min_txid" => "0000000000000009", "max_txid" => "0000000000000009", "size" => 110, "timestamp" => "2026-09-08T02:00:00Z"},
      {"level" => 9, "min_txid" => "0000000000000001", "max_txid" => "0000000000000007", "size" => 1_013, "timestamp" => "2026-09-08T03:00:00Z"}
    ]

    status_stub = proc { |path, **| (path == database_path) ? status : raise("status unavailable") }
    ltx_stub = proc { |path, **| (path == database_path) ? ltx : flunk("ltx should not run after status fails") }

    Litestream::Commands.stub :databases, databases do
      Litestream::Commands.stub :status, status_stub do
        Litestream::Commands.stub :ltx, ltx_stub do
          result = Litestream.databases

          assert_equal "[ROOT]/storage/test.sqlite3", result[0]["path"]
          assert_equal status.first, result[0]["status"]
          assert_equal({0 => 2, 9 => 1}, result[0]["levels"])
          assert_equal ltx[2], result[0]["snapshot"]
          assert_equal ltx[1], result[0]["latest"]
          assert_equal 1, result[0]["lag_txids"]
          assert_equal "status unavailable", result[1]["error"]
          assert_equal "[ROOT]/storage/failing.sqlite3", result[1]["path"]
        end
      end
    end
  end
end

require "test_helper"

class Litestream::TestProcessesController < ActionDispatch::IntegrationTest
  test "should show the process" do
    stubbed_process = {pid: "12345", status: "sleeping", started: DateTime.now}
    stubbed_databases = [
      {"path" => "[ROOT]/storage/test.sqlite3",
       "replica" => "s3",
       "status" => {"status" => "ok", "local_txid" => "000000000000000a", "wal_size" => "128 kB"},
       "ltx" => [
         {"level" => 9, "min_txid" => "0000000000000001", "max_txid" => "0000000000000009", "size" => 4_145_735, "timestamp" => "2026-09-08T03:16:43Z"}
       ],
       "levels" => {9 => 1},
       "snapshot" => {"level" => 9, "max_txid" => "0000000000000009", "size" => 4_145_735, "timestamp" => "2026-09-08T03:16:43Z"},
       "latest" => {"level" => 9, "max_txid" => "0000000000000009"},
       "lag_txids" => 1}
    ]
    Litestream.stub :replicate_process, stubbed_process do
      Litestream.stub :databases, stubbed_databases do
        get litestream.process_url
        assert_response :success

        assert_select "#process_12345", 1 do
          assert_select "small", "sleeping"
          assert_select "code", "12345"
          assert_select "time", stubbed_process[:started].to_formatted_s(:db)
        end

        assert_select "#databases li", 1 do
          assert_select "h2 code", stubbed_databases[0]["path"]
          assert_select "p", /Status:.*ok/
          assert_select "details#ltx"
          assert_select "tbody tr", 1
          assert_select "td", "9"
          assert_select "code", /0000000000000001.*0000000000000009/
        end
      end
    end
  end
end

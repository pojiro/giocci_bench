defmodule GiocciBench.PingTest do
  use ExUnit.Case

  alias GiocciBench.Ping

  @tag :tmp_dir
  test "writes ping CSV with expected columns", %{tmp_dir: tmp_dir} do
    cmd_fun = fn _cmd, _args, _opts -> {"64 bytes from 127.0.0.1: time=12.0 ms\n", 0} end

    {:ok, path} =
      Ping.run(
        ping_path: "/bin/ping",
        cmd_fun: cmd_fun,
        targets: ["127.0.0.1"],
        count: 2,
        out_dir: tmp_dir,
        run_id: "test_run"
      )

    content = File.read!(path)
    [header_line | data_lines] = String.split(content, "\r\n", trim: true)

    assert header_line == "run_id,target,iteration,elapsed_ms,success,error,started_at"
    assert length(data_lines) == 2

    rows =
      data_lines
      |> Enum.map(&String.split(&1, ","))

    assert length(rows) == 2
    [row1, row2] = rows

    keys = String.split(header_line, ",")
    row1_map = Map.new(Enum.zip(keys, row1))
    row2_map = Map.new(Enum.zip(keys, row2))

    assert row1_map["run_id"] == "test_run"
    assert row1_map["target"] == "127.0.0.1"
    assert row1_map["iteration"] == "1"
    assert row1_map["success"] == "true"
    assert row1_map["error"] == ""
    assert row1_map["started_at"] != ""
    assert row1_map["elapsed_ms"] == "12.000"
    assert row2_map["iteration"] == "2"
  end

  test "rejects non-ip targets" do
    cmd_fun = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:error, {:invalid_targets, ["localhost"]}} =
             Ping.run(
               ping_path: "/bin/ping",
               cmd_fun: cmd_fun,
               targets: ["localhost"],
               out_dir: System.tmp_dir!()
             )
  end

  describe "integration" do
    if is_nil(System.find_executable("ping")) do
      @tag skip: "ping command not available"
    end

    @tag :tmp_dir
    test "runs real ping to localhost", %{tmp_dir: tmp_dir} do
      {:ok, path} =
        Ping.run(
          targets: ["127.0.0.1"],
          count: 1,
          out_dir: tmp_dir,
          run_id: "real_ping"
        )

      content = File.read!(path)
      [header_line | data_lines] = String.split(content, "\r\n", trim: true)

      assert header_line == "run_id,target,iteration,elapsed_ms,success,error,started_at"
      assert length(data_lines) == 1

      [row] =
        data_lines
        |> Enum.map(&String.split(&1, ","))

      keys = String.split(header_line, ",")
      row_map = Map.new(Enum.zip(keys, row))

      assert row_map["success"] == "true"
      assert row_map["error"] == ""

      {elapsed_ms, _} = Float.parse(row_map["elapsed_ms"])
      assert elapsed_ms >= 0.0
    end
  end
end

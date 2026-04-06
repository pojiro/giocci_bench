defmodule GiocciBench.PingTest do
  use ExUnit.Case

  alias GiocciBench.Ping

  @tag :tmp_dir
  test "writes ping CSV with expected columns", %{tmp_dir: tmp_dir} do
    cmd_fun = fn _cmd, _args, _opts -> {"64 bytes from 127.0.0.1: time=12.0 ms\n", 0} end

    {:ok, session_dir} =
      Ping.run(
        ping_path: "/bin/ping",
        cmd_fun: cmd_fun,
        targets: ["127.0.0.1"],
        count: 2,
        out_dir: tmp_dir,
        run_id: "test_run",
        silent: true
      )

    content = File.read!(Path.join(session_dir, "ping.csv"))
    [header_line | data_lines] = String.split(content, "\r\n", trim: true)

    assert header_line == "run_id,target,iteration,elapsed_ms,success,error"
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
    assert row1_map["elapsed_ms"] == "12.000"
    assert row2_map["iteration"] == "2"
  end

  @tag :tmp_dir
  test "appends title suffix to session directory", %{tmp_dir: tmp_dir} do
    cmd_fun = fn _cmd, _args, _opts -> {"64 bytes from 127.0.0.1: time=12.0 ms\n", 0} end

    {:ok, session_dir} =
      Ping.run(
        ping_path: "/bin/ping",
        cmd_fun: cmd_fun,
        targets: ["127.0.0.1"],
        count: 1,
        out_dir: tmp_dir,
        run_id: "test_run",
        title: "nightly run",
        silent: true
      )

    assert Path.basename(session_dir) == "session_test_run_nightly run"
  end

  test "rejects non-ip targets" do
    cmd_fun = fn _cmd, _args, _opts -> {"ok", 0} end

    assert {:error, {:invalid_targets, ["localhost"]}} =
             Ping.run(
               ping_path: "/bin/ping",
               cmd_fun: cmd_fun,
               targets: ["localhost"],
               out_dir: System.tmp_dir!(),
               silent: true
             )
  end

  @tag :tmp_dir
  test "writes error when ping fails", %{tmp_dir: tmp_dir} do
    cmd_fun = fn _cmd, _args, _opts -> {"ping: unknown host\n", 1} end

    {:ok, session_dir} =
      Ping.run(
        ping_path: "/bin/ping",
        cmd_fun: cmd_fun,
        targets: ["127.0.0.1"],
        count: 1,
        out_dir: tmp_dir,
        run_id: "error_run",
        silent: true
      )

    content = File.read!(Path.join(session_dir, "ping.csv"))
    [header_line | data_lines] = String.split(content, "\r\n", trim: true)

    assert length(data_lines) == 1

    [row] =
      data_lines
      |> Enum.map(&String.split(&1, ","))

    keys = String.split(header_line, ",")
    row_map = Map.new(Enum.zip(keys, row))

    assert row_map["run_id"] == "error_run"
    assert row_map["success"] == "false"
    assert row_map["elapsed_ms"] == ""
    assert row_map["error"] == "ping: unknown host"
  end

  describe "integration" do
    if is_nil(System.find_executable("ping")) do
      @tag skip: "ping command not available"
    end

    @tag :tmp_dir
    test "runs real ping to localhost", %{tmp_dir: tmp_dir} do
      {:ok, session_dir} =
        Ping.run(
          targets: ["127.0.0.1"],
          count: 1,
          out_dir: tmp_dir,
          run_id: "real_ping",
          silent: true
        )

      content = File.read!(Path.join(session_dir, "ping.csv"))
      [header_line | data_lines] = String.split(content, "\r\n", trim: true)

      assert header_line == "run_id,target,iteration,elapsed_ms,success,error"
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

    @tag :tmp_dir
    test "records error when ping target is unreachable", %{tmp_dir: tmp_dir} do
      # 192.0.2.1 is a TEST-NET-1 address (RFC 5737) to avoid accidental reachability.
      {:ok, session_dir} =
        Ping.run(
          targets: ["192.0.2.1"],
          count: 1,
          timeout_ms: 200,
          out_dir: tmp_dir,
          run_id: "real_ping_fail",
          silent: true
        )

      content = File.read!(Path.join(session_dir, "ping.csv"))
      [header_line | data_lines] = String.split(content, "\r\n", trim: true)

      assert length(data_lines) == 1

      [row] =
        data_lines
        |> Enum.map(&String.split(&1, ","))

      keys = String.split(header_line, ",")
      row_map = Map.new(Enum.zip(keys, row))

      assert row_map["run_id"] == "real_ping_fail"
      assert row_map["success"] == "false"
      assert row_map["elapsed_ms"] == ""
      assert row_map["error"] != ""
    end
  end
end

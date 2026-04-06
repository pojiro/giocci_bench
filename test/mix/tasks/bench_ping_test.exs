defmodule Mix.Tasks.GiocciBench.PingTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.GiocciBench.Ping, as: PingTask

  defmodule PingStub do
    def run(opts) do
      send(self(), {:ping_opts, opts})
      {:ok, "tmp/session_ping"}
    end
  end

  defmodule PingErrorStub do
    def run(_opts) do
      {:error, {:invalid_targets, ["bad"]}}
    end
  end

  setup do
    original = Application.get_env(:giocci_bench, :ping_module)
    Mix.shell(Mix.Shell.Process)
    Mix.Task.clear()

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      Mix.Task.clear()

      if is_nil(original) do
        Application.delete_env(:giocci_bench, :ping_module)
      else
        Application.put_env(:giocci_bench, :ping_module, original)
      end
    end)

    :ok
  end

  test "uses defaults when no args" do
    Application.put_env(:giocci_bench, :ping_module, PingStub)

    PingTask.run([])

    assert_receive {:mix_shell, :info, ["ping measurement session created: tmp/session_ping"]}
    assert_receive {:ping_opts, opts}

    assert opts[:targets] == ["127.0.0.1"]
    assert opts[:count] == 5
    assert opts[:timeout_ms] == 1000
    assert opts[:out_dir] == "giocci_bench_output"
  end

  test "parses options" do
    Application.put_env(:giocci_bench, :ping_module, PingStub)

    PingTask.run([
      "--targets",
      "1.1.1.1, 8.8.8.8",
      "--count",
      "2",
      "--timeout-ms",
      "200",
      "--out-dir",
      "tmp_dir",
      "--title",
      "nightly"
    ])

    assert_receive {:ping_opts, opts}

    assert opts[:targets] == ["1.1.1.1", "8.8.8.8"]
    assert opts[:count] == 2
    assert opts[:timeout_ms] == 200
    assert opts[:out_dir] == "tmp_dir"
    assert opts[:title] == "nightly"
  end

  test "raises on invalid targets" do
    Application.put_env(:giocci_bench, :ping_module, PingErrorStub)

    assert_raise Mix.Error, "invalid IP targets: bad", fn ->
      PingTask.run(["--targets", "bad"])
    end
  end
end

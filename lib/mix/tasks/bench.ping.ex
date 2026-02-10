defmodule Mix.Tasks.Bench.Ping do
  use Mix.Task

  alias GiocciBench.Ping

  @shortdoc "Measure ping baseline and write CSV"

  @moduledoc """
  Measure ping response time for baseline latency.

  ## Options

    * `--targets` - Comma-separated target IPs (default: 127.0.0.1)
    * `--count` - Number of pings per target (default: 5)
    * `--timeout_ms` - Ping timeout in milliseconds (default: 1000)
    * `--out_dir` - Output directory for CSV (default: bench_output)

  """

  @impl true
  def run(args) do
    ping_module = Application.get_env(:giocci_bench, :ping_module, Ping)

    {opts, _rest, _invalid} = OptionParser.parse(args,
      switches: [targets: :string, count: :integer, timeout_ms: :integer, out_dir: :string]
    )

    targets =
      opts
      |> Keyword.get(:targets)
      |> parse_targets()

    count = Keyword.get(opts, :count, 5)
    timeout_ms = Keyword.get(opts, :timeout_ms, 1000)
    out_dir = Keyword.get(opts, :out_dir, "bench_output")

    case ping_module.run(targets: targets, count: count, timeout_ms: timeout_ms, out_dir: out_dir) do
      {:ok, path} ->
        Mix.shell().info("ping CSV written: #{path}")

      {:error, :ping_not_found} ->
        Mix.raise("ping command not found. Please install iputils/ping.")

      {:error, {:invalid_targets, invalid}} ->
        Mix.raise("invalid IP targets: #{Enum.join(invalid, ", ")}")

      {:error, reason} ->
        Mix.raise("ping measurement failed: #{inspect(reason)}")
    end
  end

  defp parse_targets(nil), do: ["127.0.0.1"]

  defp parse_targets(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> ["127.0.0.1"]
      list -> list
    end
  end
end

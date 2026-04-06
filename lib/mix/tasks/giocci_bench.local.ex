defmodule Mix.Tasks.GiocciBench.Local do
  use Mix.Task

  alias GiocciBench.Measure.Single

  @shortdoc "Measure local benchmark calls and write CSV"

  @moduledoc """
  Measure local benchmark calls (`local_exec`).

  ## Options

    * `--warmup` - Warmup iterations per case (default: 1)
    * `--iterations` - Measurement iterations per case (default: 5)
    * `--out-dir` - Output directory for CSV (default: giocci_bench_output)
    * `--no-ping` - Disable ping measurement (default: enabled)
    * `--ping-targets` - Comma-separated ping targets (default: 127.0.0.1)
    * `--ping-count` - Number of pings per target (default: 5)
    * `--include-timestamps` - Include raw measurement timestamp columns in CSV (default: disabled)
    * `--os-info` - Measure OS info around each case measurement and save CSV (default: disabled)

  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [
          warmup: :integer,
          iterations: :integer,
          out_dir: :string,
          ping: :boolean,
          ping_targets: :string,
          ping_count: :integer,
          include_timestamps: :boolean,
          os_info: :boolean
        ]
      )

    warmup = Keyword.get(opts, :warmup)
    iterations = Keyword.get(opts, :iterations)
    out_dir = Keyword.get(opts, :out_dir)
    ping = Keyword.get(opts, :ping, true)
    ping_targets = parse_ping_targets(Keyword.get(opts, :ping_targets))
    ping_count = Keyword.get(opts, :ping_count)
    include_timestamps = Keyword.get(opts, :include_timestamps, false)
    os_info = Keyword.get(opts, :os_info, false)

    {:ok, session_dir} =
      Single.run(
        warmup: warmup,
        iterations: iterations,
        out_dir: out_dir,
        cases: ["local_exec"],
        ping: ping,
        ping_targets: ping_targets,
        ping_count: ping_count,
        include_timestamps: include_timestamps,
        os_info: os_info
      )

    Mix.shell().info("measurement session created: #{session_dir}")
  end

  defp parse_ping_targets(nil), do: nil

  defp parse_ping_targets(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end

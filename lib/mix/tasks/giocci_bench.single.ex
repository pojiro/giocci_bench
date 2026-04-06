defmodule Mix.Tasks.GiocciBench.Single do
  use Mix.Task

  alias GiocciBench.Measure.Single

  @shortdoc "Measure single giocci calls and write CSV"

  @moduledoc """
  Measure single giocci calls (register_client, save_module, exec_func).

  ## Options

    * `--relay` - Relay name (default: GIOCCI_RELAY env or "giocci_relay")
    * `--warmup` - Warmup iterations per case (default: 1)
    * `--iterations` - Measurement iterations per case (default: 5)
    * `--timeout-ms` - Giocci call timeout in milliseconds (default: 5000)
    * `--out-dir` - Output directory for CSV (default: giocci_bench_output)
    * `--title` - Title suffix for session directory and metadata title
    * `--cases` - Comma-separated cases (register_client, save_module, exec_func)
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
          relay: :string,
          warmup: :integer,
          iterations: :integer,
          timeout_ms: :integer,
          out_dir: :string,
          title: :string,
          cases: :string,
          ping: :boolean,
          ping_targets: :string,
          ping_count: :integer,
          include_timestamps: :boolean,
          os_info: :boolean
        ]
      )

    relay_name = Keyword.get(opts, :relay)
    warmup = Keyword.get(opts, :warmup)
    iterations = Keyword.get(opts, :iterations)
    timeout_ms = Keyword.get(opts, :timeout_ms)
    out_dir = Keyword.get(opts, :out_dir)
    title = Keyword.get(opts, :title)
    cases = parse_cases(Keyword.get(opts, :cases))
    ping = Keyword.get(opts, :ping, true)
    ping_targets = parse_ping_targets(Keyword.get(opts, :ping_targets))
    ping_count = Keyword.get(opts, :ping_count)
    include_timestamps = Keyword.get(opts, :include_timestamps, false)
    os_info = Keyword.get(opts, :os_info, false)

    {:ok, session_dir} =
      Single.run(
        relay_name: relay_name,
        warmup: warmup,
        iterations: iterations,
        timeout_ms: timeout_ms,
        out_dir: out_dir,
        title: title,
        cases: cases,
        ping: ping,
        ping_targets: ping_targets,
        ping_count: ping_count,
        include_timestamps: include_timestamps,
        os_info: os_info
      )

    Mix.shell().info("measurement session created: #{session_dir}")
  end

  defp parse_cases(nil), do: nil

  defp parse_cases(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ping_targets(nil), do: nil

  defp parse_ping_targets(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end

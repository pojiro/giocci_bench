defmodule Mix.Tasks.GiocciBench.Local do
  use Mix.Task

  alias GiocciBench.Measure.Local

  @shortdoc "Measure local benchmark calls and write CSV"

  @moduledoc """
  Measure local benchmark calls (`local_exec`).

  ## Options

    * `--warmup` - Warmup iterations per case (default: 1)
    * `--iterations` - Measurement iterations per case (default: 5)
    * `--out-dir` - Output directory for CSV (default: giocci_bench_output)
    * `--title` - Title suffix for session directory and metadata title
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
          title: :string,
          include_timestamps: :boolean,
          os_info: :boolean
        ]
      )

    warmup = Keyword.get(opts, :warmup)
    iterations = Keyword.get(opts, :iterations)
    out_dir = Keyword.get(opts, :out_dir)
    title = Keyword.get(opts, :title)
    include_timestamps = Keyword.get(opts, :include_timestamps, false)
    os_info = Keyword.get(opts, :os_info, false)

    {:ok, session_dir} =
      Local.run(
        warmup: warmup,
        iterations: iterations,
        out_dir: out_dir,
        title: title,
        include_timestamps: include_timestamps,
        os_info: os_info
      )

    Mix.shell().info("measurement session created: #{session_dir}")
  end
end

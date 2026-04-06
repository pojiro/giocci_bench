defmodule Mix.Tasks.GiocciBench.Visualize do
  use Mix.Task

  alias GiocciBench.Visualize

  @shortdoc "Visualize benchmark CSV files as HTML report"

  @moduledoc """
  Create an HTML report from benchmark CSV files.

  By default, the latest `session_*` directory under `giocci_bench_output` is used.

  ## Options

    * `--out-dir` - Root output directory containing `session_*` (default: giocci_bench_output)
    * `--session-dir` - Explicit session directory to visualize
    * `--output` - Output HTML path (default: <session_dir>/report.html)
    * `--open` - Open generated HTML in default browser

  """

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [out_dir: :string, session_dir: :string, output: :string, open: :boolean]
      )

    out_dir = Keyword.get(opts, :out_dir, "giocci_bench_output")

    with {:ok, session_dir} <- resolve_session_dir(opts, out_dir),
         {:ok, output} <- resolve_output_path(opts, session_dir),
         {:ok, report_path} <- Visualize.generate_report(session_dir, output) do
      Mix.shell().info("visualization report created: #{report_path}")

      if Keyword.get(opts, :open, false) do
        open_in_browser(report_path)
      end
    else
      {:error, :session_not_found} ->
        Mix.raise("session directory not found. use --session-dir or check --out-dir")

      {:error, :no_csv_files} ->
        Mix.raise("no CSV files found in session directory")
    end
  end

  defp resolve_session_dir(opts, out_dir) do
    case Keyword.get(opts, :session_dir) do
      nil ->
        Visualize.latest_session_dir(out_dir)

      session_dir ->
        if File.dir?(session_dir), do: {:ok, session_dir}, else: {:error, :session_not_found}
    end
  end

  defp resolve_output_path(opts, session_dir) do
    output = Keyword.get(opts, :output, Path.join(session_dir, "report.html"))
    {:ok, output}
  end

  defp open_in_browser(path) do
    command =
      case :os.type() do
        {:unix, :darwin} -> {"open", [path]}
        {:unix, _} -> {"xdg-open", [path]}
        {:win32, _} -> {"cmd", ["/c", "start", path]}
      end

    case command do
      {cmd, argv} ->
        case System.cmd(cmd, argv, stderr_to_stdout: true) do
          {_output, 0} ->
            :ok

          {output, _status} ->
            Mix.shell().error("failed to open browser automatically: #{String.trim(output)}")
        end
    end
  rescue
    error ->
      Mix.shell().error("failed to open browser automatically: #{Exception.message(error)}")
  end
end

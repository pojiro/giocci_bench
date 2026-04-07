defmodule Mix.Tasks.GiocciBench.Visualize do
  use Mix.Task

  alias GiocciBench.Visualize

  @shortdoc "Visualize benchmark CSV files as HTML report"

  @moduledoc """
  Create an HTML report from benchmark CSV files.

  By default, the latest `session_*` directory under `giocci_bench_output` is used.

  ## Options

    * `--out-dir` - Root output directory containing `session_*` (default: giocci_bench_output)
    * `--session-dir` - Explicit session directory to visualize (supports wildcards: `*`, `?`, `[...]`; generates reports for all matching sessions)
    * `--output` - Output HTML path (default: <session_dir>/report.html; used only for single session or if wildcard matches single)
    * `--open` - Open generated HTML in default browser

  """

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [out_dir: :string, session_dir: :string, output: :string, open: :boolean]
      )

    out_dir = Keyword.get(opts, :out_dir, "giocci_bench_output")

    with {:ok, session_dirs} <- resolve_session_dirs(opts, out_dir) do
      open_flag = Keyword.get(opts, :open, false)
      custom_output = Keyword.get(opts, :output)

      session_count = length(session_dirs)

      {successes, failures} =
        session_dirs
        |> Enum.map(fn session_dir ->
          output =
            if custom_output && session_count == 1,
              do: custom_output,
              else: Path.join(session_dir, "report.html")

          {session_dir, Visualize.generate_report(session_dir, output)}
        end)
        |> Enum.split_with(fn {_dir, result} -> match?({:ok, _}, result) end)

      Enum.each(failures, fn {session_dir, {:error, reason}} ->
        Mix.shell().error("failed to generate report for #{session_dir}: #{inspect(reason)}")
      end)

      if successes == [] do
        Mix.raise("no CSV files found in any session directory")
      end

      Enum.each(successes, fn {_dir, {:ok, report_path}} ->
        Mix.shell().info("visualization report created: #{report_path}")
        if open_flag, do: open_in_browser(report_path)
      end)
    else
      {:error, :session_not_found} ->
        Mix.raise("session directory not found. use --session-dir or check --out-dir")
    end
  end

  defp resolve_session_dirs(opts, out_dir) do
    case Keyword.get(opts, :session_dir) do
      nil ->
        with {:ok, latest} <- Visualize.latest_session_dir(out_dir) do
          {:ok, [latest]}
        end

      session_dir ->
        expanded = expand_session_dir(session_dir)

        case expanded do
          [] ->
            {:error, :session_not_found}

          dirs ->
            valid_dirs = Enum.filter(dirs, &File.dir?/1)

            if valid_dirs == [] do
              {:error, :session_not_found}
            else
              {:ok, valid_dirs}
            end
        end
    end
  end

  defp expand_session_dir(path) do
    if String.contains?(path, ["*", "?", "["]) do
      Path.wildcard(path)
    else
      [path]
    end
  end

  defp open_in_browser(path) do
    command =
      case :os.type() do
        {:unix, :darwin} -> {"open", [path]}
        {:unix, _} -> {"xdg-open", [path]}
        {:win32, _} -> {"cmd", ["/c", "start", "", path]}
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

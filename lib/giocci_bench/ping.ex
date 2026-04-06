defmodule GiocciBench.Ping do
  @moduledoc false

  alias GiocciBench.Output

  @default_targets ["127.0.0.1"]
  @default_count 5
  @default_timeout_ms 1000
  @default_out_dir "giocci_bench_output"
  @columns [:run_id, :target, :iteration, :elapsed_ms, :success, :error]

  def run(opts \\ []) do
    cmd_fun = Keyword.get(opts, :cmd_fun, &System.cmd/3)
    silent = Keyword.get(opts, :silent, false)

    with {:ok, ping_path} <- fetch_ping_path(opts),
         {:ok, targets} <- validate_targets(Keyword.get(opts, :targets, @default_targets)) do
      count = Keyword.get(opts, :count, @default_count)
      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
      run_id = Keyword.get(opts, :run_id, build_run_id())

      if not silent do
        IO.puts("[Ping] Targets: #{Enum.join(targets, ", ")}, Count: #{count}")
      end

      rows = build_rows(ping_path, cmd_fun, targets, count, timeout_ms, run_id)
      title = normalize_title(Keyword.get(opts, :title))

      # セッションディレクトリを決定
      # session_dir が指定されている場合はそれを使用、
      # 指定されていない場合は out_dir から新規作成
      actual_session_dir =
        case Keyword.get(opts, :session_dir) do
          nil ->
            out_dir = Keyword.get(opts, :out_dir, @default_out_dir)
            session_dir = Path.join(out_dir, build_session_dir_name(run_id, title))
            File.mkdir_p!(session_dir)
            session_dir

          session_dir ->
            session_dir
        end

      # ping の計測結果を CSV に出力
      csv_path = Path.join(actual_session_dir, "ping.csv")
      header = header()

      Output.write_csv!(csv_path, header, rows)
      {:ok, actual_session_dir}
    end
  end

  defp build_rows(ping_path, cmd_fun, targets, count, timeout_ms, run_id) do
    for target <- targets, iteration <- 1..count do
      {elapsed_ms, success, error} = ping_once(ping_path, cmd_fun, target, timeout_ms)
      build_row(run_id, target, iteration, elapsed_ms, success, error)
    end
  end

  defp header do
    Enum.map(@columns, &Atom.to_string/1)
  end

  defp build_row(run_id, target, iteration, elapsed_ms, success, error) do
    values = %{
      run_id: run_id,
      target: target,
      iteration: iteration,
      elapsed_ms: elapsed_ms,
      success: success,
      error: error
    }

    Enum.map(@columns, &Map.fetch!(values, &1))
  end

  defp ping_once(ping_path, cmd_fun, target, timeout_ms) do
    timeout_sec = max(1, div(timeout_ms + 999, 1000))

    {output, status} =
      cmd_fun.(ping_path, ["-c", "1", "-W", Integer.to_string(timeout_sec), target],
        stderr_to_stdout: true
      )

    if status == 0 do
      case parse_ping_rtt_ms(output) do
        nil -> {nil, false, "rtt_parse_failed: #{clean_error(output)}"}
        elapsed_ms -> {elapsed_ms, true, ""}
      end
    else
      {nil, false, clean_error(output)}
    end
  end

  defp clean_error(output) do
    output
    |> String.trim()
    |> String.replace(["\r", "\n"], " ")
  end

  defp parse_ping_rtt_ms(output) do
    case Regex.run(~r/time[=<]\s*([0-9.]+)\s*ms/i, output) do
      [_, value] ->
        case Float.parse(value) do
          {rtt_ms, _} ->
            Float.round(rtt_ms, 3)

          :error ->
            nil
        end

      _ ->
        nil
    end
  end

  defp fetch_ping_path(opts) do
    case Keyword.get(opts, :ping_path) do
      nil -> fetch_ping_executable()
      path -> {:ok, path}
    end
  end

  defp fetch_ping_executable do
    case System.find_executable("ping") do
      nil -> {:error, :ping_not_found}
      path -> {:ok, path}
    end
  end

  defp validate_targets(targets) when is_list(targets) do
    invalid = Enum.reject(targets, &ip_address?/1)

    if invalid == [] do
      {:ok, targets}
    else
      {:error, {:invalid_targets, invalid}}
    end
  end

  defp ip_address?(value) when is_binary(value) do
    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp ip_address?(_value), do: false

  defp build_run_id do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d-%H%M%S")
  end

  defp build_session_dir_name(run_id, nil), do: "session_#{run_id}"
  defp build_session_dir_name(run_id, title), do: "session_#{run_id}_#{sanitize_title(title)}"

  defp normalize_title(nil), do: nil

  defp normalize_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp sanitize_title(title) do
    title
    |> String.replace(~r{[\\/]+}, "_")
    |> String.trim()
  end
end

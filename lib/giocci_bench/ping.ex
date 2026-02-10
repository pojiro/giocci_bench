defmodule GiocciBench.Ping do
  @moduledoc false

  alias GiocciBench.Csv

  @default_targets ["127.0.0.1"]
  @default_count 5
  @default_timeout_ms 1000
  @default_out_dir "bench_output"
  @columns [:run_id, :target, :iteration, :elapsed_ms, :success, :error, :started_at]

  def run(opts \\ []) do
    cmd_fun = Keyword.get(opts, :cmd_fun, &System.cmd/3)

    with {:ok, ping_path} <- fetch_ping_path(opts),
         {:ok, targets} <- validate_targets(Keyword.get(opts, :targets, @default_targets)) do
      count = Keyword.get(opts, :count, @default_count)
      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
      out_dir = Keyword.get(opts, :out_dir, @default_out_dir)
      run_id = Keyword.get(opts, :run_id, build_run_id())

      started_at = DateTime.utc_now() |> DateTime.to_iso8601()
      rows = build_rows(ping_path, cmd_fun, targets, count, timeout_ms, run_id, started_at)

      path = Path.join(out_dir, "ping_#{run_id}.csv")
      header = header()

      Csv.write_csv!(path, header, rows)
      {:ok, path}
    end
  end

  defp build_rows(ping_path, cmd_fun, targets, count, timeout_ms, run_id, started_at) do
    for target <- targets, iteration <- 1..count do
      {elapsed_ms, success, error} = ping_once(ping_path, cmd_fun, target, timeout_ms)
      build_row(run_id, target, iteration, elapsed_ms, success, error, started_at)
    end
  end

  defp header do
    Enum.map(@columns, &Atom.to_string/1)
  end

  defp build_row(run_id, target, iteration, elapsed_ms, success, error, started_at) do
    values = %{
      run_id: run_id,
      target: target,
      iteration: iteration,
      elapsed_ms: elapsed_ms,
      success: success,
      error: error,
      started_at: started_at
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
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
  end
end

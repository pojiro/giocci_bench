defmodule GiocciBench.Measure.Sequence do
  @moduledoc """
  Giocci のシーケンス計測（Sequence Measurement）を実行するモジュール。

  `register_client` -> `save_module` -> `exec_func` を連続で実行し、
  シナリオ全体の処理時間を CSV に記録します。

  ## オプション
  - `:warmup` - ウォームアップ回数（デフォルト: 1）
  - `:iterations` - 計測回数（デフォルト: 5）
  - `:os_info` - OS 情報を計測（デフォルト: false）

  詳細は `mix help giocci_bench.sequence` を参照してください。
  """

  alias GiocciBench.Output

  @default_warmup 1
  @default_iterations 5
  @default_timeout_ms 5_000
  @default_out_dir "giocci_bench_output"
  @default_ping true
  @default_os_info false
  @os_info_interval_ms 100

  @columns [
    :run_id,
    :case_id,
    :iteration,
    :elapsed_ms,
    :function_elapsed_ms,
    :warmup,
    :error
  ]

  def run(opts \\ []) do
    relay_name = fetch_option(opts, :relay_name, default_relay())
    mfargs = fetch_option(opts, :mfargs, default_mfargs())
    warmup = fetch_option(opts, :warmup, @default_warmup)
    iterations = fetch_option(opts, :iterations, @default_iterations)
    timeout_ms = fetch_option(opts, :timeout_ms, @default_timeout_ms)
    out_dir = fetch_option(opts, :out_dir, @default_out_dir)
    run_id = fetch_option(opts, :run_id, build_run_id())
    title = normalize_title(Keyword.get(opts, :title))
    ping = fetch_option(opts, :ping, @default_ping)
    ping_targets = Keyword.get(opts, :ping_targets)
    ping_count = Keyword.get(opts, :ping_count)
    os_info = fetch_option(opts, :os_info, @default_os_info)

    started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    env = env_info()

    exec_mfargs_for_meta = {Giocci, :exec_func, [relay_name, mfargs, [timeout: timeout_ms]]}

    # セッションディレクトリを作成
    session_dir = Path.join(out_dir, build_session_dir_name(run_id, title))
    File.mkdir_p!(session_dir)

    # メタデータを JSON に出力
    metadata =
      %{
        "run_id" => run_id,
        "started_at" => started_at,
        "elixir_version" => env.elixir_version,
        "otp_version" => env.otp_version,
        "os_type" => env.os_type,
        "system_arch" => env.system_arch,
        "cpu_cores" => env.cpu_cores,
        "cases" => %{"sequence" => inspect(exec_mfargs_for_meta)}
      }
      |> maybe_put_title(title)

    meta_path = Path.join(session_dir, "meta.json")
    Output.write_metadata_json!(meta_path, metadata)

    # ping が有効な場合、計測前に ping を実行
    if ping do
      :ok = run_ping_to_session(session_dir, run_id, ping_targets, ping_count)
    end

    IO.puts("\n[Sequence Measurement] Case to measure: 1")
    IO.puts("Warmup iterations: #{warmup}, Measurement iterations: #{iterations}\n")

    IO.puts("[1/1] sequence")
    :ok = warmup_runs(warmup, relay_name, mfargs, timeout_ms)

    rows =
      if os_info do
        measure_with_os_info(session_dir, "sequence", fn ->
          measure_iterations(iterations, relay_name, mfargs, run_id, warmup, timeout_ms)
        end)
      else
        measure_iterations(iterations, relay_name, mfargs, run_id, warmup, timeout_ms)
      end

    csv_path = Path.join(session_dir, "sequence.csv")
    header = Enum.map(@columns, &Atom.to_string/1)
    Output.write_csv!(csv_path, header, rows)

    {:ok, session_dir}
  end

  defp run_ping_to_session(session_dir, run_id, ping_targets, ping_count) do
    alias GiocciBench.Ping

    ping_opts = [run_id: run_id, session_dir: session_dir]

    ping_opts =
      if ping_targets, do: Keyword.put(ping_opts, :targets, ping_targets), else: ping_opts

    ping_opts = if ping_count, do: Keyword.put(ping_opts, :count, ping_count), else: ping_opts

    with {:ok, _ping_session_dir} <- Ping.run(ping_opts) do
      :ok
    else
      {:error, reason} ->
        IO.warn("ping measurement failed: #{inspect(reason)}")
        :ok
    end
  end

  # warmup: JIT コンパイルやキャッシュの初期化など、最初の実行による異常値を避けるため
  # 実際の計測前に数回実行して、システムを安定状態に導く
  defp warmup_runs(count, relay_name, mfargs, timeout_ms) when count > 0 do
    IO.write("  Warmup: ")

    for _ <- 1..count do
      case run_sequence_once(relay_name, mfargs, timeout_ms) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          raise "sequence warmup failed: #{inspect(reason)}"
      end

      IO.write(".")
    end

    IO.puts(" done")
    :ok
  end

  defp warmup_runs(_count, _relay_name, _mfargs, _timeout_ms), do: :ok

  defp measure_iterations(
         _case_id,
         iterations,
         _mfargs,
         _run_id,
         _warmup_count,
         _columns
       )
       when iterations < 1 do
    raise ArgumentError, "iterations must be >= 1, got: #{iterations}"
  end

  defp measure_iterations(iterations, relay_name, mfargs, run_id, warmup_count, timeout_ms) do
    IO.write("  Measuring: ")

    rows =
      for iteration <- 1..iterations do
        {elapsed_ms, sequence_result} = timed_sequence_call(relay_name, mfargs, timeout_ms)

        values =
          case sequence_result do
            {:ok, result} ->
              %{
                run_id: run_id,
                case_id: "sequence",
                iteration: iteration,
                elapsed_ms: elapsed_ms,
                function_elapsed_ms: extract_function_elapsed_ms(result),
                warmup: warmup_count,
                error: nil
              }

            {:error, reason} ->
              %{
                run_id: run_id,
                case_id: "sequence",
                iteration: iteration,
                elapsed_ms: nil,
                function_elapsed_ms: nil,
                warmup: warmup_count,
                error: inspect(reason)
              }
          end

        IO.write(".")
        Enum.map(@columns, &Map.get(values, &1))
      end

    IO.puts(" done")
    rows
  end

  defp run_sequence_once(relay_name, {m, _f, _args} = mfargs, timeout_ms) do
    with :ok <- Giocci.register_client(relay_name, timeout: timeout_ms),
         :ok <- Giocci.save_module(relay_name, m, timeout: timeout_ms) do
      case Giocci.exec_func(relay_name, mfargs, timeout: timeout_ms) do
        {:error, reason} -> {:error, reason}
        result -> {:ok, result}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp timed_sequence_call(relay_name, mfargs, timeout_ms) do
    start_time = System.os_time()
    result = run_sequence_once(relay_name, mfargs, timeout_ms)
    end_time = System.os_time()

    elapsed_ms =
      (end_time - start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {elapsed_ms, result}
  end

  defp extract_function_elapsed_ms({_value, function_time}), do: function_time
  defp extract_function_elapsed_ms(_result), do: nil

  defp measure_with_os_info(session_dir, case_id, measure_fun) when is_function(measure_fun, 0) do
    prefix = "#{case_id}_os_info"

    case OsInfoMeasurer.start(session_dir, prefix, @os_info_interval_ms) do
      :ok ->
        try do
          measure_fun.()
        after
          case OsInfoMeasurer.stop() do
            :ok -> :ok
            {:error, reason} -> IO.warn("os_info measurement stop failed: #{inspect(reason)}")
          end
        end

      {:error, reason} ->
        IO.warn("os_info measurement start failed: #{inspect(reason)}")
        measure_fun.()
    end
  end

  defp fetch_option(opts, key, default) do
    case Keyword.fetch(opts, key) do
      {:ok, nil} -> default
      {:ok, value} -> value
      :error -> default
    end
  end

  defp env_info do
    %{
      elixir_version: System.version(),
      otp_version: System.otp_release(),
      os_type: os_type(),
      system_arch: system_arch(),
      cpu_cores: cpu_cores()
    }
  end

  defp os_type do
    {family, name} = :os.type()
    "#{family}-#{name}"
  end

  defp system_arch do
    :erlang.system_info(:system_architecture)
    |> List.to_string()
  end

  defp cpu_cores do
    case :erlang.system_info(:logical_processors_available) do
      :unknown ->
        case :erlang.system_info(:logical_processors_online) do
          :unknown -> nil
          value -> value
        end

      value ->
        value
    end
  end

  defp build_run_id do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d-%H%M%S")
  end

  defp maybe_put_title(metadata, nil), do: metadata
  defp maybe_put_title(metadata, title), do: Map.put(metadata, "title", title)

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

  defp default_relay do
    System.get_env("GIOCCI_RELAY", "giocci_relay")
  end

  defp default_mfargs do
    Application.get_env(
      :giocci_bench,
      :measure_mfargs,
      Application.get_env(
        :giocci_bench,
        :sequence_measure_mfargs,
        {GiocciBench.Samples.Add, :run, [[1, 2]]}
      )
    )
  end
end

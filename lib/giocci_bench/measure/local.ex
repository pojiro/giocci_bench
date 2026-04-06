defmodule GiocciBench.Measure.Local do
  @moduledoc """
  ローカル比較計測（Local Measurement）を実行するモジュール。

  サンプルモジュールをローカルで直接実行し、処理時間を CSV に記録します。

  ## 計測項目
  - `local_exec` - ローカル関数実行（比較用）

  ## オプション
  - `:warmup` - ウォームアップ回数（デフォルト: 1）
  - `:iterations` - 計測回数（デフォルト: 5）
  - `:include_timestamps` - タイムスタンプ列を出力（デフォルト: false）
  - `:os_info` - OS 情報を計測（デフォルト: false）

  詳細は `mix help giocci_bench.local` を参照してください。
  """

  alias GiocciBench.Output

  @default_warmup 1
  @default_iterations 5
  @default_out_dir "giocci_bench_output"
  @default_include_timestamps false
  @default_os_info false
  @os_info_interval_ms 100

  @base_columns [
    :run_id,
    :case_id,
    :iteration,
    :elapsed_ms,
    :function_elapsed_ms,
    :warmup
  ]

  @calculated_columns [
    :client_to_relay,
    :relay_to_client,
    :relay_to_engine,
    :engine_to_relay,
    :client_to_engine,
    :engine_to_client
  ]

  @timestamp_columns [
    :client_send_timestamp_to_relay,
    :relay_recv_timestamp_from_client,
    :relay_send_timestamp_to_client,
    :client_recv_timestamp_from_relay,
    :relay_send_timestamp_to_engine,
    :engine_recv_timestamp_from_relay,
    :engine_send_timestamp_to_relay,
    :relay_recv_timestamp_from_engine,
    :client_send_timestamp_to_engine,
    :engine_recv_timestamp_from_client,
    :engine_send_timestamp_to_client,
    :client_recv_timestamp_from_engine
  ]

  def run(opts \\ []) do
    mfargs = fetch_option(opts, :mfargs, default_mfargs())
    warmup = fetch_option(opts, :warmup, @default_warmup)
    iterations = fetch_option(opts, :iterations, @default_iterations)
    out_dir = fetch_option(opts, :out_dir, @default_out_dir)
    run_id = fetch_option(opts, :run_id, build_run_id())
    title = normalize_title(Keyword.get(opts, :title))
    include_timestamps = fetch_option(opts, :include_timestamps, @default_include_timestamps)
    os_info = fetch_option(opts, :os_info, @default_os_info)

    started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    env = env_info()

    session_dir = Path.join(out_dir, build_session_dir_name(run_id, title))
    File.mkdir_p!(session_dir)

    metadata =
      %{
        "run_id" => run_id,
        "started_at" => started_at,
        "elixir_version" => env.elixir_version,
        "otp_version" => env.otp_version,
        "os_type" => env.os_type,
        "system_arch" => env.system_arch,
        "cpu_cores" => env.cpu_cores,
        "cases" => %{"local_exec" => inspect(mfargs)}
      }
      |> maybe_put_title(title)

    meta_path = Path.join(session_dir, "meta.json")
    Output.write_metadata_json!(meta_path, metadata)

    IO.puts("\n[Local Measurement] Case to measure: 1")
    IO.puts("Warmup iterations: #{warmup}, Measurement iterations: #{iterations}\n")

    columns = build_columns(include_timestamps)
    header = Enum.map(columns, &Atom.to_string/1)

    IO.puts("[1/1] local_exec")
    :ok = warmup_runs(warmup, mfargs)

    rows =
      if os_info do
        measure_with_os_info(session_dir, "local_exec", fn ->
          measure_iterations(iterations, mfargs, run_id, warmup, columns)
        end)
      else
        measure_iterations(iterations, mfargs, run_id, warmup, columns)
      end

    csv_path = Path.join(session_dir, "local_exec.csv")
    Output.write_csv!(csv_path, header, rows)

    {:ok, session_dir}
  end

  defp warmup_runs(count, mfargs) when count > 0 do
    IO.write("  Warmup: ")

    for _ <- 1..count do
      {mod, func, args} = mfargs
      apply(mod, func, args)
      IO.write(".")
    end

    IO.puts(" done")
    :ok
  end

  defp warmup_runs(_count, _mfargs), do: :ok

  defp measure_iterations(iterations, _mfargs, _run_id, _warmup_count, _columns)
       when iterations < 1 do
    raise ArgumentError, "iterations must be >= 1, got: #{iterations}"
  end

  defp measure_iterations(iterations, mfargs, run_id, warmup_count, columns) do
    IO.write("  Measuring: ")

    rows =
      for iteration <- 1..iterations do
        {elapsed_ms, result} = timed_call(mfargs)

        function_elapsed_ms = extract_function_elapsed_ms(result)

        values = %{
          run_id: run_id,
          case_id: "local_exec",
          iteration: iteration,
          elapsed_ms: elapsed_ms,
          function_elapsed_ms: function_elapsed_ms,
          warmup: warmup_count
        }

        IO.write(".")
        Enum.map(columns, &Map.get(values, &1))
      end

    IO.puts(" done")
    rows
  end

  defp timed_call({mod, func, args}) do
    start_time = System.os_time()
    result = apply(mod, func, args)
    end_time = System.os_time()

    case result do
      {:error, reason} ->
        raise "local call failed: #{inspect(reason)}"

      _ ->
        elapsed_ms =
          (end_time - start_time)
          |> System.convert_time_unit(:native, :microsecond)
          |> Kernel./(1000)
          |> Float.round(3)

        {elapsed_ms, result}
    end
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

  defp build_columns(include_timestamps) do
    if include_timestamps do
      @base_columns ++ @calculated_columns ++ @timestamp_columns
    else
      @base_columns ++ @calculated_columns
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

  defp default_mfargs do
    Application.get_env(
      :giocci_bench,
      :measure_mfargs,
      Application.get_env(
        :giocci_bench,
        :local_measure_mfargs,
        Application.get_env(
          :giocci_bench,
          :single_measure_mfargs,
          {GiocciBench.Samples.Add, :run, [[1, 2]]}
        )
      )
    )
  end
end

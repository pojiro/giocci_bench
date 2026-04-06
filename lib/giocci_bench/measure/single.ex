defmodule GiocciBench.Measure.Single do
  @moduledoc """
  Giocci の単体計測（Single Measurement）を実行するモジュール。

  各 giocci 関数（`register_client`, `save_module`, `exec_func`）を
  個別に計測し、処理時間と通信時間を CSV に記録します。

  複合計測（複数の関数を連続実行）とは異なり、各関数を独立して計測します。

  ## 計測項目
  - `register_client` - クライアント登録
  - `save_module` - モジュール保存
  - `exec_func` - リモート関数実行
  - `local_exec` - ローカル関数実行（比較用、`mix giocci_bench.local` で実行）

  ## オプション
  - `:warmup` - ウォームアップ回数（デフォルト: 1）
  - `:iterations` - 計測回数（デフォルト: 5）
  - `:include_timestamps` - タイムスタンプ列を出力（デフォルト: false）
  - `:os_info` - OS 情報を計測（デフォルト: false）

  詳細は `mix help giocci_bench.single` を参照してください。
  """

  alias GiocciBench.Output

  @default_warmup 1
  @default_iterations 5
  @default_timeout_ms 5_000
  @default_out_dir "giocci_bench_output"
  @single_cases ["register_client", "save_module", "exec_func"]
  @local_case "local_exec"
  @supported_cases @single_cases ++ [@local_case]
  @default_cases @single_cases
  @default_ping true
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
    relay_name = fetch_option(opts, :relay_name, default_relay())
    mfargs = fetch_option(opts, :mfargs, default_mfargs())
    {module, func, args} = mfargs
    warmup = fetch_option(opts, :warmup, @default_warmup)
    iterations = fetch_option(opts, :iterations, @default_iterations)
    timeout_ms = fetch_option(opts, :timeout_ms, @default_timeout_ms)
    out_dir = fetch_option(opts, :out_dir, @default_out_dir)
    run_id = fetch_option(opts, :run_id, build_run_id())
    ping = fetch_option(opts, :ping, @default_ping)
    ping_targets = Keyword.get(opts, :ping_targets)
    ping_count = Keyword.get(opts, :ping_count)
    include_timestamps = fetch_option(opts, :include_timestamps, @default_include_timestamps)
    os_info = fetch_option(opts, :os_info, @default_os_info)

    started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    env = env_info()
    selected_cases = normalize_cases(fetch_option(opts, :cases, @default_cases))

    # ベンチマーク対象のケースを定義
    # 各要素は {case_id, mfargs} のタプル：
    #   - case_id: ケースの識別子（文字列）。結果CSVで使用、filter時の判定キー
    #   - mfargs: {module, function, args} を表すタプル
    cases = [
      {"register_client",
       {Giocci, :register_client, [relay_name, [timeout: timeout_ms, measure_to: nil]]}},
      {"save_module",
       {Giocci, :save_module, [relay_name, module, [timeout: timeout_ms, measure_to: nil]]}},
      {"exec_func",
       {Giocci, :exec_func, [relay_name, mfargs, [timeout: timeout_ms, measure_to: nil]]}},
      {"local_exec", {module, func, args}}
    ]

    filtered_cases = Enum.filter(cases, fn {case_id, _mfargs} -> case_id in selected_cases end)

    # セッションディレクトリを作成
    session_dir = Path.join(out_dir, "session_#{run_id}")
    File.mkdir_p!(session_dir)

    # case_id → mfargs のマップを作成
    cases_mapping =
      filtered_cases
      |> Enum.map(fn {case_id, mfargs} -> {case_id, inspect(mfargs)} end)
      |> Map.new()

    # メタデータを JSON に出力
    metadata = %{
      "run_id" => run_id,
      "started_at" => started_at,
      "elixir_version" => env.elixir_version,
      "otp_version" => env.otp_version,
      "os_type" => env.os_type,
      "system_arch" => env.system_arch,
      "cpu_cores" => env.cpu_cores,
      "cases" => cases_mapping
    }

    meta_path = Path.join(session_dir, "meta.json")
    Output.write_metadata_json!(meta_path, metadata)

    # ping が有効な場合、計測前に ping を実行
    if ping do
      :ok = run_ping_to_session(session_dir, run_id, ping_targets, ping_count)
    end

    total_cases = Enum.count(filtered_cases)
    IO.puts("\n[Single Measurement] Cases to measure: #{total_cases}")
    IO.puts("Warmup iterations: #{warmup}, Measurement iterations: #{iterations}\n")

    columns = build_columns(include_timestamps)
    header = Enum.map(columns, &Atom.to_string/1)

    filtered_cases
    |> Enum.with_index(1)
    |> Enum.each(fn {{case_id, mfargs}, case_index} ->
      IO.puts("[#{case_index}/#{total_cases}] #{case_id}")
      :ok = prepare_case(case_id, relay_name, module, timeout_ms)
      :ok = warmup_runs(warmup, mfargs, case_id)

      rows =
        if os_info do
          measure_with_os_info(session_dir, case_id, fn ->
            measure_iterations(case_id, iterations, mfargs, run_id, warmup, columns)
          end)
        else
          measure_iterations(case_id, iterations, mfargs, run_id, warmup, columns)
        end

      # 各 case_id ごとに CSV ファイルに出力
      csv_path = Path.join(session_dir, "#{case_id}.csv")
      Output.write_csv!(csv_path, header, rows)
    end)

    {:ok, session_dir}
  end

  defp run_ping_to_session(session_dir, run_id, ping_targets, ping_count) do
    alias GiocciBench.Ping

    ping_opts = [run_id: run_id, session_dir: session_dir]

    ping_opts =
      if ping_targets, do: Keyword.put(ping_opts, :targets, ping_targets), else: ping_opts

    ping_opts = if ping_count, do: Keyword.put(ping_opts, :count, ping_count), else: ping_opts

    # ping を実行して結果を取得
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
  # warmup では測定値を取得しないため measure_to: nil を渡す
  defp warmup_runs(count, mfargs, _case_id) when count > 0 do
    IO.write("  Warmup: ")

    measure_to = nil

    for _ <- 1..count do
      {mod, func, args} = ensure_measure_to(mfargs, measure_to)
      apply(mod, func, args)
      IO.write(".")
    end

    IO.puts(" done")
    :ok
  end

  defp warmup_runs(_count, _mfargs, _case_id), do: :ok

  defp measure_iterations(
         case_id,
         iterations,
         mfargs,
         run_id,
         warmup_count,
         columns
       ) do
    IO.write("  Measuring: ")

    measure_to = if case_id == "local_exec", do: nil, else: self()
    mfargs = ensure_measure_to(mfargs, measure_to)

    results =
      for iteration <- 1..iterations do
        {elapsed_ms, result} = timed_call(mfargs)

        # giocci から測定値を受信
        measurements =
          if measure_to do
            receive do
              {:giocci_measurements, m} -> m
            after
              1000 -> %{}
            end
          else
            %{}
          end

        # exec_func と local_exec の場合のみ function_elapsed_ms を取得
        function_elapsed_ms =
          if case_id in ["exec_func", "local_exec"] do
            {_value, function_time} = result
            function_time
          else
            nil
          end

        values =
          %{
            run_id: run_id,
            case_id: case_id,
            iteration: iteration,
            elapsed_ms: elapsed_ms,
            function_elapsed_ms: function_elapsed_ms,
            warmup: warmup_count
          }
          |> Map.merge(measurements)

        IO.write(".")
        Enum.map(columns, &Map.get(values, &1))
      end

    IO.puts(" done")
    results
  end

  defp timed_call({mod, func, args}) do
    start_time = System.os_time()
    result = apply(mod, func, args)
    end_time = System.os_time()

    case result do
      {:error, reason} ->
        raise "giocci call failed: #{inspect(reason)}"

      _ ->
        elapsed_ms =
          (end_time - start_time)
          |> System.convert_time_unit(:native, :microsecond)
          |> Kernel./(1000)
          |> Float.round(3)

        {elapsed_ms, result}
    end
  end

  defp ensure_measure_to({mod, func, args}, measure_to) when is_list(args) do
    updated_args =
      with opts when is_list(opts) <- List.last(args),
           true <- Keyword.keyword?(opts),
           true <- Keyword.has_key?(opts, :measure_to) do
        List.replace_at(args, -1, Keyword.put(opts, :measure_to, measure_to))
      else
        _ -> args
      end

    {mod, func, updated_args}
  end

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

  defp prepare_case("register_client", _relay_name, _module, _timeout_ms), do: :ok

  defp prepare_case("save_module", relay_name, _module, timeout_ms) do
    :ok = Giocci.register_client(relay_name, timeout: timeout_ms)
  end

  defp prepare_case("exec_func", relay_name, module, timeout_ms) do
    :ok = Giocci.register_client(relay_name, timeout: timeout_ms)
    :ok = Giocci.save_module(relay_name, module, timeout: timeout_ms)
  end

  defp prepare_case("local_exec", _relay_name, _module, _timeout_ms), do: :ok

  defp fetch_option(opts, key, default) do
    case Keyword.fetch(opts, key) do
      {:ok, nil} -> default
      {:ok, value} -> value
      :error -> default
    end
  end

  defp normalize_cases(cases) when is_list(cases) do
    normalized = Enum.map(cases, &to_string/1)
    invalid = Enum.reject(normalized, &(&1 in @supported_cases))

    if invalid == [] do
      normalized
    else
      raise "unknown cases: #{Enum.join(invalid, ", ")}"
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

  defp default_relay do
    System.get_env("GIOCCI_RELAY", "giocci_relay")
  end

  defp default_mfargs do
    Application.get_env(
      :giocci_bench,
      :single_measure_mfargs,
      {GiocciBench.Samples.Add, :run, [[1, 2]]}
    )
  end
end

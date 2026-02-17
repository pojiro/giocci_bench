defmodule GiocciBench.Measure.Single do
  @moduledoc false

  alias GiocciBench.Output

  @default_warmup 1
  @default_iterations 5
  @default_timeout_ms 5_000
  @default_out_dir "giocci_bench_output"
  @default_cases ["register_client", "save_module", "exec_func", "local_exec"]
  @default_ping true
  @columns [
    :run_id,
    :case_id,
    :case_desc,
    :iteration,
    :elapsed_ms,
    :engine_elapsed_ms,
    :warmup
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

    started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    env = env_info()
    selected_cases = normalize_cases(fetch_option(opts, :cases, @default_cases))

    # local_exec の case_desc を動的に生成
    local_exec_desc =
      "#{Module.split(module) |> Enum.join(".")}.#{func}/#{length(args)}"

    # ベンチマーク対象の3つのケースを定義
    # 各要素は {case_id, case_desc, fun} のタプル：
    #   - case_id: ケースの識別子（文字列）。結果CSVで使用、filter時の判定キー
    #   - case_desc: Giocciのメソッドシグネチャなど、ケース説明（文字列）。CSV出力に含まれる
    #   - fun: 実際に実行する無名関数。warmup_runs と measure_iterations で呼び出される
    cases = [
      {"register_client", "Giocci.register_client/2",
       fn -> Giocci.register_client(relay_name, timeout: timeout_ms) end},
      {"save_module", "Giocci.save_module/3",
       fn -> Giocci.save_module(relay_name, module, timeout: timeout_ms) end},
      {"exec_func", "Giocci.exec_func/3",
       fn -> Giocci.exec_func(relay_name, mfargs, timeout: timeout_ms) end},
      {"local_exec", local_exec_desc, fn -> apply(module, func, args) end}
    ]

    filtered_cases =
      cases
      |> Enum.filter(fn {case_id, _case_desc, _fun} -> case_id in selected_cases end)

    # セッションディレクトリを作成
    session_dir = Path.join(out_dir, "session_#{run_id}")
    File.mkdir_p!(session_dir)

    # メタデータを JSON に出力
    metadata = %{
      "run_id" => run_id,
      "started_at" => started_at,
      "elixir_version" => env.elixir_version,
      "otp_version" => env.otp_version,
      "os" => env.os,
      "cpu" => env.cpu,
      "cpu_cores" => env.cpu_cores
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

    rows =
      filtered_cases
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{case_id, case_desc, fun}, case_index} ->
        case_display =
          if case_id in ["exec_func", "local_exec"] do
            {module, func, args} = mfargs

            "#{case_desc} (module: #{inspect(module)}, func: #{inspect(func)}, args: #{inspect(args)})"
          else
            case_desc
          end

        IO.puts("[#{case_index}/#{total_cases}] #{case_display}")
        :ok = prepare_case(case_id, relay_name, module, timeout_ms)
        :ok = warmup_runs(warmup, fun)
        measure_iterations(case_id, case_desc, iterations, fun, run_id, warmup)
      end)

    # 計測結果を CSV に出力
    csv_path = Path.join(session_dir, "single.csv")
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
  defp warmup_runs(count, fun) when count > 0 do
    IO.write("  Warmup: ")

    for _ <- 1..count do
      fun.()
      IO.write(".")
    end

    IO.puts(" done")
    :ok
  end

  defp warmup_runs(_count, _fun), do: :ok

  defp measure_iterations(
         case_id,
         case_desc,
         iterations,
         fun,
         run_id,
         warmup_count
       ) do
    IO.write("  Measuring: ")

    results =
      for iteration <- 1..iterations do
        {elapsed_ms, result} = timed_call(fun)

        # exec_func と local_exec の場合のみ engine_elapsed_ms を取得
        engine_elapsed_ms =
          if case_id in ["exec_func", "local_exec"] do
            {_value, engine_time} = result
            engine_time
          else
            nil
          end

        values = %{
          run_id: run_id,
          case_id: case_id,
          case_desc: case_desc,
          iteration: iteration,
          elapsed_ms: elapsed_ms,
          engine_elapsed_ms: engine_elapsed_ms,
          warmup: warmup_count
        }

        IO.write(".")
        Enum.map(@columns, &Map.fetch!(values, &1))
      end

    IO.puts(" done")
    results
  end

  defp timed_call(fun) do
    start_time = System.monotonic_time()
    result = fun.()

    case result do
      {:error, reason} ->
        raise "giocci call failed: #{inspect(reason)}"

      _ ->
        elapsed_ms =
          System.monotonic_time()
          |> Kernel.-(start_time)
          |> System.convert_time_unit(:native, :microsecond)
          |> Kernel./(1000)
          |> Float.round(3)

        {elapsed_ms, result}
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
    invalid = Enum.reject(normalized, &(&1 in @default_cases))

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
      os: os_string(),
      cpu: cpu_arch(),
      cpu_cores: cpu_cores()
    }
  end

  defp os_string do
    {family, name} = :os.type()
    "#{family}-#{name}"
  end

  defp cpu_arch do
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
    |> DateTime.to_unix(:millisecond)
    |> Integer.to_string()
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

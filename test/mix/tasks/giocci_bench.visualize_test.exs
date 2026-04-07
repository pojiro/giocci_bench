defmodule Mix.Tasks.GiocciBench.VisualizeTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.GiocciBench.Visualize, as: VisualizeTask

  setup do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.clear()

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      Mix.Task.clear()
    end)

    :ok
  end

  @tag :tmp_dir
  test "creates report from explicit session directory", %{tmp_dir: tmp_dir} do
    session_dir = Path.join(tmp_dir, "session_20260406-120000")
    File.mkdir_p!(session_dir)

    csv = [
      "run_id,case_id,iteration,elapsed_ms,function_elapsed_ms,warmup,error",
      "20260406-120000,sequence,1,100.0,80.0,1,",
      "20260406-120000,sequence,2,110.0,85.0,1,"
    ]

    File.write!(Path.join(session_dir, "sequence.csv"), Enum.join(csv, "\n"))

    File.write!(
      Path.join(session_dir, "meta.json"),
      ~s({"title":"nightly","cases":{"sequence":"{Giocci, :exec_func, [\"relay\", {M, :run, [[1,2]]}, [timeout: 5000]]}"}})
    )

    VisualizeTask.run(["--session-dir", session_dir])

    report_path = Path.join(session_dir, "report.html")
    assert File.exists?(report_path)

    report = File.read!(report_path)
    assert report =~ "\"name\": \"elapsed_ms\""
    assert report =~ "\"session_title\": \"nightly\""
    assert report =~ "\"mfargs\""
    assert report =~ "\"sequence\""
    assert report =~ "\"csv_file\""
    assert report =~ "\"svg_file\""

    exported_csvs = Path.wildcard(Path.join(session_dir, "report/*.csv"))
    assert exported_csvs != []

    exported_svgs = Path.wildcard(Path.join(session_dir, "report/*.svg"))
    assert exported_svgs != []

    assert_receive {:mix_shell, :info, [message]}
    assert message =~ "visualization report created:"
  end

  @tag :tmp_dir
  test "uses latest session under out-dir", %{tmp_dir: tmp_dir} do
    out_dir = Path.join(tmp_dir, "giocci_bench_output")
    older = Path.join(out_dir, "session_20260406-100000")
    newer = Path.join(out_dir, "session_20260406-101000")
    File.mkdir_p!(older)
    File.mkdir_p!(newer)

    File.write!(
      Path.join(older, "sequence.csv"),
      "run_id,case_id,iteration,elapsed_ms\n1,sequence,1,1.0\n"
    )

    File.write!(
      Path.join(newer, "sequence.csv"),
      "run_id,case_id,iteration,elapsed_ms\n1,sequence,1,2.0\n"
    )

    VisualizeTask.run(["--out-dir", out_dir])

    assert File.exists?(Path.join(newer, "report.html"))
    refute File.exists?(Path.join(older, "report.html"))
  end

  @tag :tmp_dir
  test "uses default report title when title is missing", %{tmp_dir: tmp_dir} do
    session_dir = Path.join(tmp_dir, "session_20260406-120100")
    File.mkdir_p!(session_dir)

    File.write!(
      Path.join(session_dir, "sequence.csv"),
      "run_id,case_id,iteration,elapsed_ms\n1,sequence,1,1.0\n"
    )

    File.write!(
      Path.join(session_dir, "meta.json"),
      ~s({"measure_mfargs":"{GiocciBench.Samples.Sieve, :run, [[1000000]]}","cases":{"sequence":"{Giocci, :exec_func, [\"relay\", {GiocciBench.Samples.Sieve, :run, [[1000000]]}, [timeout: 5000]]}"}})
    )

    VisualizeTask.run(["--session-dir", session_dir])

    report = File.read!(Path.join(session_dir, "report.html"))
    refute report =~ "\"display_title\""
    assert report =~ "\"title\": \"Giocci Bench Visualization\""
    assert report =~ "\"mfargs\""
  end

  @tag :tmp_dir
  test "orders sections for single report", %{tmp_dir: tmp_dir} do
    session_dir = Path.join(tmp_dir, "session_20260406-130000-single")
    File.mkdir_p!(session_dir)

    base_csv = "run_id,case_id,iteration,elapsed_ms\n1,case,1,1.0\n"
    os_csv = "time[ms],user,idle\n1,10,90\n2,11,91\n"

    File.write!(
      Path.join(session_dir, "ping.csv"),
      "run_id,target,iteration,elapsed_ms,success,error\n1,127.0.0.1,1,0.1,true,\n"
    )

    File.write!(Path.join(session_dir, "register_client.csv"), base_csv)
    File.write!(Path.join(session_dir, "save_module.csv"), base_csv)
    File.write!(Path.join(session_dir, "exec_func.csv"), base_csv)
    File.write!(Path.join(session_dir, "register_client_os_info_proc_stat.csv"), os_csv)
    File.write!(Path.join(session_dir, "save_module_os_info_proc_stat.csv"), os_csv)
    File.write!(Path.join(session_dir, "exec_func_os_info_proc_stat.csv"), os_csv)

    File.write!(
      Path.join(session_dir, "register_client_os_info_free.csv"),
      "time[ms],total[KiB]\n1,100\n"
    )

    File.write!(
      Path.join(session_dir, "save_module_os_info_free.csv"),
      "time[ms],total[KiB]\n1,100\n"
    )

    File.write!(
      Path.join(session_dir, "exec_func_os_info_free.csv"),
      "time[ms],total[KiB]\n1,100\n"
    )

    VisualizeTask.run(["--session-dir", session_dir])

    report = File.read!(Path.join(session_dir, "report.html"))

    assert order_in_text(report, [
             "\"title\": \"ping.csv\"",
             "\"title\": \"register_client.csv\"",
             "\"title\": \"save_module.csv\"",
             "\"title\": \"exec_func.csv\"",
             "\"title\": \"register_client_os_info_proc_stat.csv\"",
             "\"title\": \"save_module_os_info_proc_stat.csv\"",
             "\"title\": \"exec_func_os_info_proc_stat.csv\"",
             "\"title\": \"register_client_os_info_free.csv\"",
             "\"title\": \"save_module_os_info_free.csv\"",
             "\"title\": \"exec_func_os_info_free.csv\""
           ])
  end

  defp order_in_text(text, patterns) do
    {_ok, _last} =
      Enum.reduce_while(patterns, {:ok, -1}, fn pattern, {:ok, last_index} ->
        case :binary.match(text, pattern) do
          {index, _length} when index > last_index ->
            {:cont, {:ok, index}}

          _ ->
            {:halt, {:error, {pattern, last_index}}}
        end
      end)

    true
  end
end

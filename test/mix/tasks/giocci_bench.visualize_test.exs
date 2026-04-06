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

    VisualizeTask.run(["--session-dir", session_dir])

    report_path = Path.join(session_dir, "report.html")
    assert File.exists?(report_path)

    report = File.read!(report_path)
    assert report =~ "\"name\": \"elapsed_ms\""

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
end

defmodule GiocciBench.Samples.BigBeam do
  @big_binary :binary.copy(<<0>>, 1024 * 1024 * 10)

  @behaviour GiocciBench.Samples.BenchmarkBehaviour

  @spec run(list()) :: {:ok, float()}
  @impl true
  def run([]) do
    start_time = System.monotonic_time()
    result = File.write!("/dev/null", @big_binary)
    end_time = System.monotonic_time()

    elapsed_ms =
      (end_time - start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {result, elapsed_ms}
  end
end

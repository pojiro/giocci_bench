defmodule GiocciBench.Samples.Add do
  @moduledoc "Simple arithmetic addition (lightweight benchmark)"

  @behaviour GiocciBench.Samples.BenchmarkBehaviour

  @spec run(list()) :: {integer(), float()}
  @impl true
  def run([a, b]) do
    start_time = System.monotonic_time()
    result = a + b

    elapsed_ms =
      System.monotonic_time()
      |> Kernel.-(start_time)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)
      |> Float.round(3)

    {result, elapsed_ms}
  end
end

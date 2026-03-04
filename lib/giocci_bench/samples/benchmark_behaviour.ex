defmodule GiocciBench.Samples.BenchmarkBehaviour do
  @moduledoc "Behaviour for benchmark sample modules"

  @doc """
  Execute a benchmark operation and return the result with elapsed time in milliseconds.

  Each implementation must:
  1. Accept arguments as a list
  2. Measure execution time using System.monotonic_time()
  3. Return a tuple {result, elapsed_ms} where:
     - result: The result of the operation
     - elapsed_ms: Time taken in milliseconds (as float with 3 decimal places)

  ## Important Note

  When used with `Giocci.exec_func/3`, the mfargs is `{module, func, args}` where
  `args` is a list passed to `apply/3`. Since `run/1` expects a list argument,
  you must wrap the arguments in a nested list:

      # Correct: args = [[1_000_000]] -> apply(Sieve, :run, [[1_000_000]]) -> Sieve.run([1_000_000])
      # Wrong:   args = [1_000_000]  -> apply(Sieve, :run, [1_000_000])  -> Sieve.run(1_000_000)

  ## Examples

      iex> GiocciBench.Samples.Add.run([1, 2])
      {3, 0.123}

      iex> GiocciBench.Samples.Sieve.run([100])
      {25, 1.456}
  """
  @callback run(args :: list()) :: {result :: any(), elapsed_ms :: float()}
end

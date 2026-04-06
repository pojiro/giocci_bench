defmodule GiocciBench.MixProject do
  use Mix.Project

  def project do
    [
      app: :giocci_bench,
      version: "0.3.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:giocci, "== 0.4.1", runtime: Mix.env() != :test},
      {:nimble_csv, "~> 1.2"},
      {:os_info_measurer,
       git: "https://github.com/biyooon-ex/os_info_measurer.git", tag: "v0.1.3"}
    ]
  end
end

import Config

config :giocci,
  zenoh_config_file_path: System.get_env("GIOCCI_ZENOH_CONFIG", "config/zenoh.json5"),
  client_name: System.get_env("GIOCCI_CLIENT_NAME", "giocci_bench"),
  key_prefix: System.get_env("GIOCCI_KEY_PREFIX", "")

config :giocci_bench,
  single_measure_mfargs: {GiocciBench.Samples.Sieve, :sieve, [1_000_000]}

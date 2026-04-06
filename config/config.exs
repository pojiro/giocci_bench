import Config

config :giocci,
  zenoh_config_file_path: System.get_env("GIOCCI_ZENOH_CONFIG", "config/zenoh.json5"),
  client_name: System.get_env("GIOCCI_CLIENT_NAME", "giocci_bench"),
  key_prefix: System.get_env("GIOCCI_KEY_PREFIX", "")

config :giocci_bench,
  # measure_mfargs: {module, func, args}
  # IMPORTANT: args is a list passed to apply/3.
  # If the sample module's run/1 expects a list as its argument,
  # you must wrap it: [[arg1, arg2, ...]] not [arg1, arg2, ...]
  # Example: For Sieve.run([1_000_000]), use [[1_000_000]]
  #          For Add.run([1, 2]), use [[1, 2]]
  measure_mfargs: {GiocciBench.Samples.Sieve, :run, [[1_000_000]]}

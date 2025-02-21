import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :risteys, Risteys.Repo,
  username: System.get_env("TEST_DATABASE_USERNAME") || "postgres",
  password: System.get_env("TEST_DATABASE_PASSWORD") || "postgres",
  hostname: System.get_env("TEST_DATABASE_HOST") || "localhost",
  database: "risteys_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :risteys, RisteysWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JYgEJqcLAHg/s6T0UTRAZxRR1n2QtWVFLBhVRJNwP37Zj2cSU2b/iFxb1m1a5uhU",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

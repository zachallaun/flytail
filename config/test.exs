import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flytail, FlytailWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "vV5+RX9OLbMjN3IHyuDC138tQ6Mq/3mCxldrYqrenj4YBI9zTuhc27oYWxWSt+Yo",
  server: false

# In test we don't send emails.
config :flytail, Flytail.Mailer,
  adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

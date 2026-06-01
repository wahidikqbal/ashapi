import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ashapi start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ashapi, AshapiWeb.Endpoint, server: true
end

config :ashapi, AshapiWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ashapi, Ashapi.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :ashapi, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ashapi, AshapiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :ashapi,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # CORS Configuration for production runtime
  # Set CORS_ALLOWED_ORIGINS environment variable with comma-separated origins
  # Example: CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com
  cors_origins_env = System.get_env("CORS_ALLOWED_ORIGINS", "")

  cors_allowed_origins =
    if cors_origins_env == "" do
      raise """
      environment variable CORS_ALLOWED_ORIGINS is missing.
      Set it to a comma-separated list of allowed origins, e.g.:
      CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com
      """
    else
      cors_origins_env
      |> String.split(",")
      |> Enum.map(&String.trim/1)
    end

  config :ashapi, :cors, allowed_origins: cors_allowed_origins

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ashapi, AshapiWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ashapi, AshapiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Mailer configuration
  mailer_adapter = System.get_env("MAILER_ADAPTER", "mailgun")

  adapter_module =
    case mailer_adapter do
      "postmark" -> Swoosh.Adapters.Postmark
      "sendgrid" -> Swoosh.Adapters.Sendgrid
      "smtp" -> Swoosh.Adapters.SMTP
      _ -> Swoosh.Adapters.Mailgun
    end

  mailer_config = [
    adapter: adapter_module
  ]

  mailer_config =
    case mailer_adapter do
      "mailgun" ->
        Keyword.put(mailer_config, :api_key, System.get_env("MAILGUN_API_KEY"))
        |> Keyword.put(:domain, System.get_env("MAILGUN_DOMAIN"))

      "postmark" ->
        Keyword.put(mailer_config, :api_key, System.get_env("POSTMARK_API_KEY"))

      "sendgrid" ->
        Keyword.put(mailer_config, :api_key, System.get_env("SENDGRID_API_KEY"))

      _ ->
        mailer_config
    end

  config :ashapi, Ashapi.Mailer, mailer_config

  from_name = System.get_env("MAILER_FROM_NAME", "Ashapi")
  from_email = System.get_env("MAILER_FROM_EMAIL", "noreply@example.com")

  config :ashapi, :mailer,
    from_address: {from_name, from_email},
    from_email: from_email
end

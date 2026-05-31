defmodule AshapiWeb.Plugs.AuthPlug do
  import Plug.Conn

  require Logger

  alias AshAuthentication.Jwt

  def init(opts), do: opts

  def call(conn, _opts) do
    token = conn.cookies["token"]

    case token do
      nil ->
        conn

      token ->
        case Jwt.verify(token, Ashapi.Accounts.User) do
          {:ok, user} ->
            Logger.debug("JWT verified for user #{user.id}")

            assign(conn, :current_user, user)

          {:error, reason} ->
            Logger.warning("JWT verification failed: #{inspect(reason)}")

            conn

          other ->
            Logger.warning("Unexpected JWT verify result: #{inspect(other)}")

            conn
        end
    end
  end
end
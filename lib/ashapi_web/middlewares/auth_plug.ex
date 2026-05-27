defmodule AshapiWeb.Plugs.AuthPlug do
  import Plug.Conn

  alias AshAuthentication.Jwt

  def init(opts), do: opts

  def call(conn, _opts) do
    token = conn.cookies["token"]

    if token do
      case Jwt.verify(token, Ashapi.Accounts.User) do
        {:ok, user} ->
          assign(conn, :current_user, user)

        _ ->
          conn
      end
    else
      conn
    end
  end
end
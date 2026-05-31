defmodule AshapiWeb.Plugs.TokenFromCookie do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cookie_name = Application.get_env(:ashapi, :token_cookie_name, "token")

    case conn.cookies[cookie_name] do
      nil ->
        conn

      token when is_binary(token) and token != "" ->
        put_req_header(conn, "authorization", "Bearer #{token}")

      _ ->
        conn
    end
  end
end
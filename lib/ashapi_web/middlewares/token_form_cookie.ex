defmodule AshapiWeb.Plugs.TokenFromCookie do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.cookies["token"] do
      nil ->
        # No cookie token, check for Bearer token in Authorization header instead
        conn

      token when is_binary(token) and token != "" ->
        # Inject token into Authorization header for AshAuthentication to process
        # This way both cookie-based and header-based auth work
        put_req_header(conn, "authorization", "Bearer #{token}")

      _ ->
        # Invalid token format
        conn
    end
  end
end
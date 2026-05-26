defmodule AshapiWeb.Plugs.TokenFromCookie do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do

    conn = fetch_cookies(conn)

    case conn.cookies["token"] do
      nil   -> conn  # tidak ada cookie, lanjut (mungkin pakai header)
      
      token ->
        # masukkan ke Authorization header agar AshAuthentication bisa baca
        put_req_header(conn, "authorization", "Bearer #{token}")
    end
  end
end
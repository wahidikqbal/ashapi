# plug tambahan untuk validasi origin
defmodule AshapiWeb.Plugs.CheckOrigin do
  import Plug.Conn

  #@allowed_origins ["https://yourdomain.com"] # ganti dengan domain frontend Anda, pada saat development bisa diatur ke ["http://localhost:3000"] atau ["*"] untuk menerima semua origin (tidak disarankan untuk production)
  @allowed_origins ["*"] # untuk kemudahan testing, menerima semua origin. Ganti dengan domain frontend Anda saat deploy ke production.
  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    if origin in @allowed_origins or "*" in @allowed_origins do
      conn
    else
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end
end
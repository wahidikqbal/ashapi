defmodule AshapiWeb.Plugs.AuthPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:user] do
      assign(conn, :current_user, conn.assigns[:user])
    else
      conn
    end
  end
end

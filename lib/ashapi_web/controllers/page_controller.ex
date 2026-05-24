defmodule AshapiWeb.PageController do
  use AshapiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

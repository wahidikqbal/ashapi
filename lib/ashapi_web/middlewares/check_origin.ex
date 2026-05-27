# plug tambahan untuk validasi origin
defmodule AshapiWeb.Plugs.CheckOrigin do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()
    cors_config = Application.get_env(:ashapi, :cors, []) || []
    allowed_origins =
      case cors_config do
        list when is_list(list) -> Keyword.get(list, :allowed_origins, [])
        map when is_map(map) -> Map.get(map, :allowed_origins, []) || []
        _ -> []
      end

    cond do
      is_nil(origin) ->
        # No origin header - allow (requests without origin like direct API calls)
        conn

      origin in allowed_origins ->
        # Origin is allowed
        conn

      "*" in allowed_origins ->
        # Wildcard allowed (not recommended for production)
        conn

      true ->
        # Origin not allowed - reject
        conn
        |> send_resp(403, "Forbidden - Origin not allowed")
        |> halt()
    end
  end
end
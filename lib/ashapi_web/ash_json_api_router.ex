defmodule AshapiWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Ashapi.Blog],
    open_api: "/open_api",
    json_schema: "/json_schema",
    prefix: "/api/json"

end

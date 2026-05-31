defmodule AshapiWeb.Plugs.RateLimiter do
  import Plug.Conn

  @table :rate_limiter
  @window_ms 60_000

  def init(opts), do: Keyword.get(opts, :max, 20)

  def call(conn, max_requests) do
    init_table()

    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    window = now_window()
    key = {ip, window}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if count > max_requests do
      body = Jason.encode!(%{error: "Too many requests. Try again later."})

      conn
      |> put_resp_content_type("application/json")
      |> put_status(:too_many_requests)
      |> put_resp_header("retry-after", "60")
      |> send_resp(429, body)
      |> halt()
    else
      conn
    end
  end

  defp init_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, write_concurrency: true])
      _ -> :ok
    end
  end

  defp now_window do
    now = System.system_time(:millisecond)
    now - rem(now, @window_ms)
  end

  def start_link(_opts) do
    Task.start_link(&cleanup_loop/0)
  end

  defp cleanup_loop do
    init_table()

    receive do
    after
      @window_ms ->
        now = now_window()
        :ets.foldl(
          fn {key = {_ip, window}, _count}, :ok ->
            if window < now, do: :ets.delete(@table, key)
            :ok
          end,
          :ok,
          @table
        )

        cleanup_loop()
    end
  end
end

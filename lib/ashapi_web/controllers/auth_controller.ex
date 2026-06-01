defmodule AshapiWeb.AuthController do
  use AshapiWeb, :controller
  require Ash.Query

  # POST /api/auth/login
  def login(conn, params) do
    attributes = get_in(params, ["data", "attributes"]) || %{}

    case Ashapi.Accounts.User
         |> Ash.Query.for_read(:sign_in_with_password, attributes)
         |> Ash.read_one() do
      {:ok, user} ->
        access_token = user.__metadata__.token
        refresh_token = user.__metadata__.refresh_token

        conn
        |> put_resp_cookie(cookie_name(), refresh_token,
          http_only: true,
          secure: cookie_secure?(),
          same_site: "Strict",
          path: "/",
          max_age: 604_800
        )
        |> json(%{
          success: true,
          access_token: access_token,
          message: "You are now signed in"
        })

      {:error, _error} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          success: false,
          error: "Incorrect email or password"
        })
    end
  end

  # POST /api/auth/refresh
  def refresh(conn, _params) do
    refresh_token = conn.cookies[cookie_name()]

    if refresh_token do
      case Ashapi.Accounts.User
           |> Ash.Query.for_read(:exchange_refresh_token, %{refresh_token: refresh_token})
           |> Ash.read_one() do
        {:ok, user} ->
          new_access_token = user.__metadata__.token
          new_refresh_token = user.__metadata__.refresh_token

          conn
          |> put_resp_cookie(cookie_name(), new_refresh_token,
            http_only: true,
            secure: cookie_secure?(),
            same_site: "Strict",
            path: "/",
            max_age: 604_800
          )
          |> json(%{access_token: new_access_token})

        {:error, _reason} ->
          conn
          |> delete_resp_cookie(cookie_name())
          |> put_status(:unauthorized)
          |> json(%{error: "Invalid or expired refresh token"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "No refresh token provided"})
    end
  end

  # POST /api/auth/logout
  def logout(conn, _params) do
    current_user = conn.assigns[:current_user]

    if current_user do
      revoke_all_tokens_for_subject("user?id=#{current_user.id}")
    end

    conn
    |> delete_resp_cookie(cookie_name())
    |> put_status(:ok)
    |> json(%{success: true, message: "Logged out"})
  end

  # GET /api/auth/me
  def me(conn, _params) do
    current_user = conn.assigns[:current_user]

    if current_user do
      json(conn, %{
        authenticated: true,
        user: %{
          id: current_user.id,
          email: current_user.email
        }
      })
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{authenticated: false})
    end
  end

  defp revoke_all_tokens_for_subject(subject) do
    case Ashapi.Accounts.Token
         |> Ash.Query.new()
         |> Ash.Query.filter(subject: subject)
         |> Ash.read() do
      {:ok, []} ->
        :ok

      {:ok, tokens} ->
        Enum.each(tokens, fn token ->
          token
          |> Ash.Changeset.for_update(:revoke_all_stored_for_subject, %{subject: subject})
          |> Ash.update()
        end)

      _ ->
        :ok
    end
  end

  defp cookie_name do
    Application.get_env(:ashapi, :refresh_token_cookie_name, "refresh_token")
  end

  defp cookie_secure? do
    Application.get_env(:ashapi, :cookie_secure, false)
  end
end

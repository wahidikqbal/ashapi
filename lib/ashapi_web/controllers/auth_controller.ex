defmodule AshapiWeb.AuthController do
  use AshapiWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> put_resp_cookie(cookie_name(), token,
        path: "/",
        http_only: true,
        secure: cookie_secure?(),
        same_site: "Strict",
        max_age: 86_400
      )
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Incorrect email or password")
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> revoke_token()
    |> configure_session(drop: true)
    |> delete_resp_cookie(cookie_name())
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end

  def login(conn, params) do
    attributes =
      get_in(params, ["data", "attributes"]) || %{}

    case Ashapi.Accounts.User
         |> Ash.Query.for_read(
              :sign_in_with_password,
              attributes
            )
         |> Ash.read_one() do
      {:ok, user} ->
        token =
          user.__metadata__.token

        conn
        |> assign(:current_user, user)
        |> put_resp_cookie(
             cookie_name(),
             token,
             http_only: true,
             secure: cookie_secure?(),
             same_site: "Strict",
             max_age: 86_400
           )
        |> json(%{
             success: true,
             message: "You are now signed in",
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

  def logout(conn, _params) do
    conn
    |> revoke_token()
    |> delete_resp_cookie(cookie_name())
    |> put_status(:ok)
    |> json(%{
      success: true,
      message: "Logged out"
    })
  end

  defp cookie_name do
    Application.get_env(:ashapi, :token_cookie_name, "token")
  end

  defp cookie_secure? do
    Application.get_env(:ashapi, :cookie_secure, false)
  end

  defp revoke_token(conn) do
    conn = fetch_cookies(conn)

    case get_token_from_conn(conn) do
      nil ->
        conn

      token ->
        case AshAuthentication.TokenResource.revoke(
              Ashapi.Accounts.Token,
              token
            ) do
          :ok ->
            IO.puts("TOKEN REVOKED")

          {:error, error} ->
            IO.inspect(error, label: "REVOKE ERROR")

          other ->
            IO.inspect(other, label: "REVOKE RESULT")
        end

        conn
    end
  end

  defp get_token_from_conn(conn) do
    conn.cookies[cookie_name()] ||
      conn
      |> get_req_header("authorization")
      |> List.first()
      |> strip_bearer()
  end

  defp strip_bearer("Bearer " <> token), do: token
  defp strip_bearer("bearer " <> token), do: token
  defp strip_bearer(_), do: nil

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
      |> json(%{
          authenticated: false
        })
    end
  end
end

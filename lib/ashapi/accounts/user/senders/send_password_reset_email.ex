defmodule Ashapi.Accounts.User.Senders.SendPasswordResetEmail do
  use AshAuthentication.Sender

  import Swoosh.Email

  alias Ashapi.Mailer

  @impl true
  def send(user, token, _) do
    from_address =
      Application.get_env(:ashapi, :mailer, [])
      |> Keyword.get(:from_address, {"Ashapi", "noreply@example.com"})

    frontend_url = Application.get_env(:ashapi, :frontend_url, "http://localhost:4321")

    new()
    |> from(from_address)
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body(body(token: token, frontend_url: frontend_url))
    |> Mailer.deliver!()
  end

  defp body(params) do
    url = "#{params[:frontend_url]}/reset-password/#{params[:token]}"

    """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    """
  end
end

defmodule Ashapi.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
  """

  use AshAuthentication.Sender
  use AshapiWeb, :verified_routes

  import Swoosh.Email

  alias Ashapi.Mailer

  @impl true
  def send(user, token, _) do
    from_address = Application.get_env(:ashapi, :mailer, []) |> Keyword.get(:from_address, {"Ashapi", "noreply@example.com"})

    new()
    |> from(from_address)
    |> to(to_string(user.email))
    |> subject("Confirm your email address")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    url = url(~p"/confirm_new_user/#{params[:token]}")

    """
    <p>Click this link to confirm your email:</p>
    <p><a href="#{url}">#{url}</a></p>
    """
  end
end

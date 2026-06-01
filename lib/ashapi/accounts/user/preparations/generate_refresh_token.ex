defmodule Ashapi.Accounts.User.Preparations.GenerateRefreshToken do
  use Ash.Resource.Preparation

  def prepare(query, _options, _context) do
    Ash.Query.after_action(query, fn _query, users ->
      case users do
        [user] ->
          token = Ash.Resource.get_metadata(user, :token)

          if token do
            case AshAuthentication.Jwt.token_for_user(
                   user,
                   %{"purpose" => "refresh_token"},
                   token_lifetime: {7, :days}
                 ) do
              {:ok, refresh_token, _claims} ->
                user = Ash.Resource.put_metadata(user, :refresh_token, refresh_token)
                {:ok, [user]}

              {:error, reason} ->
                {:error, reason}
            end
          else
            {:ok, users}
          end

        _ ->
          {:ok, users}
      end
    end)
  end
end

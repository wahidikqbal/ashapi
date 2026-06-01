defmodule Ashapi.Accounts.User.Preparations.ExchangeRefreshToken do
  use Ash.Resource.Preparation

  alias Ash.Query
  alias Ash.Resource
  alias AshAuthentication.Jwt

  def prepare(query, options, context) do
    {:ok, strategy} = AshAuthentication.Info.find_strategy(query, context, options)

    query
    |> Query.before_action(&verify_token(&1, strategy, context))
    |> Query.after_action(&revoke_refresh_token(&1, &2, strategy, context))
    |> Query.after_action(&generate_new_tokens(&1, &2, strategy, context))
  end

  defp verify_token(query, strategy, context) do
    token = Query.get_argument(query, :refresh_token)

    with {:ok, _claims, _} <-
           Jwt.verify(token, strategy.resource, Ash.Context.to_opts(context)),
         :ok <- verify_token_purpose(token) do
      query
    else
      {:error, reason} -> Query.add_error(query, :refresh_token, reason)
    end
  end

  defp verify_token_purpose(token) do
    case Jwt.peek(token) do
      {:ok, %{"purpose" => "refresh_token"}} -> :ok
      {:ok, _} -> {:error, "Token purpose is not refresh_token"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revoke_refresh_token(query, [user], _strategy, _context) do
    token = Query.get_argument(query, :refresh_token)

    case revoke_by_jti(token) do
      :ok -> {:ok, [user]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revoke_refresh_token(_query, result, _strategy, _context), do: {:ok, result}

  defp revoke_by_jti(token) do
    case Jwt.peek(token) do
      {:ok, claims} ->
        jti = claims["jti"]
        subject = claims["sub"]

        case Ash.create(
               Ash.Changeset.for_create(
                 Ashapi.Accounts.Token,
                 :revoke_jti,
                 %{jti: jti, subject: subject}
               )
             ) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_new_tokens(_query, [user], _strategy, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, refresh_token, _claims} <-
           Jwt.token_for_user(
             user,
             %{"purpose" => "refresh_token"},
             Keyword.put(opts, :token_lifetime, {7, :days})
           ),
         {:ok, token, _claims} <-
           Jwt.token_for_user(user, %{"purpose" => :user}, opts) do
      user =
        user
        |> Resource.put_metadata(:refresh_token, refresh_token)
        |> Resource.put_metadata(:token, token)

      {:ok, [user]}
    end
  end

  defp generate_new_tokens(_query, result, _strategy, _context), do: {:ok, result}
end

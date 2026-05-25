defmodule Ashapi.Accounts do
  use Ash.Domain, 
  otp_app: :ashapi, 
  extensions: [AshAdmin.Domain, AshJsonApi.Domain]

  admin do
    show? true
  end

  resources do
    resource Ashapi.Accounts.Token
    resource Ashapi.Accounts.User
  end
end

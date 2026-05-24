defmodule Ashapi.Blog do
  use Ash.Domain,
    otp_app: :ashapi,
    extensions: [AshJsonApi.Domain]

  resources do
    resource Ashapi.Blog.Post
  end
end

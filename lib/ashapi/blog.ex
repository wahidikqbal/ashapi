defmodule Ashapi.Blog do
  use Ash.Domain,
    otp_app: :ashapi

  resources do
    resource Ashapi.Blog.Post
  end
end

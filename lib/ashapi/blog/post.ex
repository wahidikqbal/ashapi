defmodule Ashapi.Blog.Post do
  use Ash.Resource, 
    otp_app: :ashapi, 
    domain: Ashapi.Blog, 
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "posts"
    repo Ashapi.Repo
  end

  actions do
    defaults [:read, :destroy, create: [:title, :content], update: [:title, :content]]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      public? true
    end

    timestamps()
  end

  json_api do
    type "post"

    routes do
      base "/posts"

      get :read
      index :read

      post :create

      patch :update
      delete :destroy
    end
  end
end

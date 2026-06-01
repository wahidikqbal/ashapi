# Seeds — Data awal untuk development
#
# Jalankan: mix run priv/repo/seeds.exs

Ashapi.Repo.start_link()

IO.puts("🌱 Seeding database...")

# ── Test User ──────────────────────────────────────────────
email = "admin@admin.com"
password = "password123"

case Ashapi.Accounts.User
     |> Ash.Query.for_read(:get_by_email, %{email: email})
     |> Ash.read_one(actor: :none) do
  {:ok, %Ashapi.Accounts.User{}} ->
    IO.puts("  ⏭️  User #{email} already exists, skipping.")

  _ ->
    case Ashapi.Accounts.User
         |> Ash.Changeset.for_create(:register_with_password, %{
           email: email,
           password: password,
           password_confirmation: password
         })
         |> Ash.create(authorize?: false) do
      {:ok, _user} ->
        IO.puts("  ✅ User created: #{email} / #{password}")

      {:error, error} ->
        IO.puts("  ❌ Failed to create user: #{inspect(error)}")
    end
end

# ── Sample Posts ──────────────────────────────────────────
posts = [
  %{
    title: "Getting Started with Ash Framework",
    content:
      "Ash Framework is a declarative application framework for Elixir. It provides a rich set of tools for building domain-driven applications."
  },
  %{
    title: "Why Elixir Matters in 2026",
    content:
      "Elixir continues to gain traction for building scalable, fault-tolerant systems. With its Ruby-like syntax and Erlang-grade concurrency, it's a compelling choice for modern backends."
  },
  %{
    title: "Phoenix LiveView vs JavaScript SPAs",
    content:
      "LiveView offers a compelling alternative to JavaScript SPAs by rendering UI on the server and updating the client via WebSockets. This reduces frontend complexity significantly."
  }
]

for attrs <- posts do
  case Ashapi.Blog.Post
       |> Ash.Changeset.for_create(:create, attrs)
       |> Ash.create(authorize?: false) do
    {:ok, _post} ->
      IO.puts("  ✅ Post created: #{attrs.title}")

    {:error, error} ->
      IO.puts("  ❌ Failed to create post: #{inspect(error)}")
  end
end

IO.puts("🌱 Done!")

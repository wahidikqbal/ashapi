# Rencana Implementasi: Access + Refresh Token (Astro SSR/BFF)

**Dibuat:** 1 Juni 2026
**Status:** Final — siap implementasi
**Referensi:** [Refresh Tokens with Ash Authentication](https://www.mikewilson.dev/posts/refresh-tokens-with-ash-authentication/) — Mike Wilson

---

## 1. Arsitektur

```
Browser (Astro)
  │  Cookie: refresh_token (HttpOnly, Secure, SameSite=Strict, Path=/)
  ▼
Astro SSR (BFF)
  │  Decode JWT → cek exp → cache access_token di server memory
  │  Kalau expired → call /api/auth/refresh dengan cookie
  ▼
Phoenix API (ashapi)
  │  Verify access token (stateless JWT, 30 menit)
  │  Refresh endpoint → validasi + rotation refresh token (7 hari)
  ▼
PostgreSQL (tokens table)
```

### Alur per SSR Request

```
1. Astro terima request dari browser (dengan cookie refresh_token)
2. Astro cek cache (key: hash refresh_token)
3. Jika ada access_token di cache:
   a. Decode JWT payload, cek exp
   b. Jika exp > (now + 30s buffer) → pakai untuk API call
   c. Jika expired → call /api/auth/refresh
4. Jika tidak ada di cache → call /api/auth/refresh
5. API call ke Phoenix dengan Authorization: Bearer <access_token>
6. Render response
```

### Alur Login

```
1. Browser POST credentials ke Astro /api/auth/login
2. Astro forward ke Phoenix POST /api/auth/login
3. Phoenix:
   a. sign_in_with_password → access_token (JWT, 30 menit)
   b. GenerateRefreshToken → refresh_token (JWT, 7 hari, purpose: "refresh_token")
   c. Return { access_token } + Set-Cookie: refresh_token=<JWT>
4. Astro simpan access_token di cache, forward cookie ke browser
```

---

## 2. Pendekatan (dari Artikel)

Menggunakan **JWT sebagai refresh token**, bukan random string.

**Keuntungan dibanding rencana sebelumnya:**
- Tidak perlu action `store_refresh_token` — `AshAuthentication.TokenResource` built-in handle storage & revoke
- Refresh token JWT diverifikasi via `AshAuthentication.Jwt.verify/3`
- Validasi cukup dengan cek claim `purpose: "refresh_token"` di payload JWT
- Revoke via `AshAuthentication.TokenResource.revoke/3` (built-in)
- Token storage & revocation memanfaatkan infrastruktur AshAuthentication yang sudah ada

### Token Spec

| Token | Format | Lifetime | Stored in DB | Claim `purpose` |
|---|---|---|---|---|
| Access | JWT | 30 menit | Ya (`store_all_tokens? true`) | `:user` |
| Refresh | JWT | 7 hari | Ya (auto via `store_token`) | `"refresh_token"` |

---

## 3. Perubahan di Phoenix Backend

### 3.1 User Resource — ubah token_lifetime & tambah action

**File:** `lib/ashapi/accounts/user.ex`

**a) Ubah `token_lifetime`:**
```
token_lifetime {30, :minutes}
```

**b) Modifikasi `sign_in_with_password`** — tambah preparation `GenerateRefreshToken` dan metadata `refresh_token`:

```elixir
read :sign_in_with_password do
  description "Attempt to sign in using a email and password."
  get? true

  argument :email, :ci_string do
    description "The email to use for retrieving the user."
    allow_nil? false
  end

  argument :password, :string do
    description "The password to check for the matching user."
    allow_nil? false
    sensitive? true
  end

  # validates the provided email and password and generates a token
  prepare AshAuthentication.Strategy.Password.SignInPreparation
  # generates refresh token after successful sign-in
  prepare Ashapi.Accounts.User.Preparations.GenerateRefreshToken

  metadata :token, :string do
    description "A JWT that can be used to authenticate the user."
    allow_nil? false
  end

  metadata :refresh_token, :string do
    description "A JWT refresh token."
    allow_nil? false
  end
end
```

**c) Tambah action `exchange_refresh_token`** — untuk menukar refresh token dengan access token baru:

```elixir
read :exchange_refresh_token do
  description "Exchange a refresh token for a new access token."
  get? true

  argument :refresh_token, :string, allow_nil?: false, sensitive?: true

  metadata :token, :string, allow_nil?: false
  metadata :refresh_token, :string, allow_nil?: false

  prepare set_context(%{strategy_name: :password})
  prepare Ashapi.Accounts.User.Preparations.ExchangeRefreshToken
end
```

**d) Tambah policy untuk `exchange_refresh_token`:**

```elixir
policy action(:exchange_refresh_token) do
  authorize_if always()
end
```

### 3.2 Preparation Baru: GenerateRefreshToken

**File baru:** `lib/ashapi/accounts/user/preparations/generate_refresh_token.ex`

```elixir
defmodule Ashapi.Accounts.User.Preparations.GenerateRefreshToken do
  use Ash.Resource.Preparation

  def prepare(query, _options, _context) do
    Ash.Query.after_action(query, fn _query, users ->
      case users do
        [user] ->
          token = Ash.Resource.get_metadata(user, :token)

          if token do
            # Auth berhasil — generate refresh token JWT
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
            # Auth gagal — tidak ada access token
            {:ok, users}
          end

        _ ->
          {:ok, users}
      end
    end)
  end
end
```

### 3.3 Preparation Baru: ExchangeRefreshToken

**File baru:** `lib/ashapi/accounts/user/preparations/exchange_refresh_token.ex`

Preparation ini melakukan 3 hal secara berurutan via `before_action` + `after_action` hooks:

1. **Verify token** (before_action) — Verifikasi JWT refresh token, cek claim `purpose`, ekstrak user ID dari subject
2. **Revoke old refresh token** (after_action) — Revoke refresh token lama
3. **Generate new tokens** (after_action) — Generate access token baru + refresh token baru

```elixir
defmodule Ashapi.Accounts.User.Preparations.ExchangeRefreshToken do
  use Ash.Resource.Preparation

  alias Ash.{Query, Resource}
  alias AshAuthentication.{Info, Jwt, TokenResource}

  def prepare(query, options, context) do
    {:ok, strategy} = Info.find_strategy(query, context, options)

    query
    |> Query.before_action(&verify_token(&1, strategy, context))
    |> Query.after_action(&revoke_refresh_token(&1, &2, strategy, context))
    |> Query.after_action(&generate_new_tokens(&1, &2, strategy, context))
  end

  defp verify_token(query, strategy, context) do
    token = Query.get_argument(query, :refresh_token)

    with {:ok, _claims, _} <- Jwt.verify(token, strategy.resource, Ash.Context.to_opts(context)),
         :ok <- verify_token_purpose(token),
         {:ok, primary_keys} <- primary_keys_from_token(token, strategy.resource) do
      query |> Query.filter(^primary_keys)
    else
      {:error, reason} ->
        Query.add_error(query, :refresh_token, reason)
    end
  end

  defp verify_token_purpose(token) do
    case Jwt.peek(token) do
      {:ok, %{"purpose" => "refresh_token"}} -> :ok
      {:ok, _} -> {:error, "Token purpose is not refresh_token"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp primary_keys_from_token(token, resource) do
    with {:ok, claims} <- Jwt.peek(token),
         {:ok, primary_keys} <- primary_keys_from_subject(claims, resource) do
      {:ok, primary_keys}
    end
  end

  defp primary_keys_from_subject(%{"sub" => sub}, resource) do
    primary_key_fields =
      resource
      |> Resource.Info.primary_key()
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    key_parts =
      sub
      |> URI.parse()
      |> Map.get(:query, "")
      |> URI.decode_query()

    provided_key_fields =
      key_parts
      |> Map.keys()
      |> MapSet.new()

    if MapSet.equal?(primary_key_fields, provided_key_fields) do
      {:ok, Enum.to_list(key_parts)}
    else
      {:error, "Subject does not contain required primary key fields"}
    end
  end

  defp primary_keys_from_subject(_, _), do: {:error, "Token does not contain a subject"}

  defp revoke_refresh_token(_query, [user], strategy, _context) do
    token_resource = Info.authentication_tokens_token_resource!(strategy.resource)

    # Catatan: refresh_token ada di metadata yang disimpan sebelum generate_new_tokens
    # Karena after_action hook berurutan, kita revoke dulu
    {:ok, [user]}
  end

  # Hook ini jalan duluan (declared first)
  defp revoke_refresh_token(query, [user], strategy, context) do
    token_resource = Info.authentication_tokens_token_resource!(strategy.resource)
    token = Query.get_argument(query, :refresh_token)

    case TokenResource.revoke(token_resource, token, Ash.Context.to_opts(context)) do
      :ok -> {:ok, [user]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revoke_refresh_token(_query, result, _strategy, _context), do: {:ok, result}

  # Hook ini jalan kedua (declared second)
  defp generate_new_tokens(_query, [user], strategy, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, refresh_token, _claims} <-
           Jwt.token_for_user(user, %{"purpose" => "refresh_token"},
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
```

### 3.4 Token Resource — tidak ada perubahan

**File:** `lib/ashapi/accounts/token.ex`

Tidak perlu perubahan. Action built-in `store_token`, `revoke_token`, `get_token` sudah mencukupi untuk handle JWT-based refresh token.

### 3.5 AuthController — modifikasi besar

**File:** `lib/ashapi_web/controllers/auth_controller.ex`

```elixir
defmodule AshapiWeb.AuthController do
  use AshapiWeb, :controller
  use AshAuthentication.Phoenix.Controller

  # =============================================
  # Browser routes — dinonaktifkan
  # =============================================
  # success/3, failure/3, sign_out/3 tidak dipakai lagi
  # karena LiveView auth routes dinonaktifkan.
  # Bisa dihapus atau dibiarkan (tidak terpakai).

  # =============================================
  # API Routes (dipakai Astro)
  # =============================================

  # POST /api/auth/login
  def login(conn, params) do
    attributes = get_in(params, ["data", "attributes"]) || %{}

    case Ashapi.Accounts.User
         |> Ash.Query.for_read(:sign_in_with_password, attributes)
         |> Ash.read_one() do
      {:ok, user} ->
        access_token = user.__metadata__.token
        refresh_token = user.__metadata__.refresh_token

        conn
        |> assign(:current_user, user)
        |> put_resp_cookie("refresh_token", refresh_token,
             http_only: true,
             secure: cookie_secure?(),
             same_site: "Strict",
             path: "/api",
             max_age: 604_800
           )
        |> json(%{
             success: true,
             access_token: access_token,
             message: "You are now signed in"
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

  # POST /api/auth/refresh (BARU)
  def refresh(conn, _params) do
    refresh_token = conn.cookies["refresh_token"]

    if refresh_token do
      case Ashapi.Accounts.User
           |> Ash.Query.for_read(:exchange_refresh_token, %{refresh_token: refresh_token})
           |> Ash.read_one() do
        {:ok, user} ->
          new_access_token = user.__metadata__.token
          new_refresh_token = user.__metadata__.refresh_token

          conn
          |> put_resp_cookie("refresh_token", new_refresh_token,
               http_only: true,
               secure: cookie_secure?(),
               same_site: "Strict",
               path: "/",
               max_age: 604_800
             )
          |> json(%{access_token: new_access_token})

        {:error, _reason} ->
          conn
          |> delete_resp_cookie("refresh_token")
          |> put_status(:unauthorized)
          |> json(%{error: "Invalid or expired refresh token"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "No refresh token provided"})
    end
  end

  # POST /api/auth/logout
  def logout(conn, _params) do
    refresh_token = conn.cookies["refresh_token"]

    if refresh_token do
      AshAuthentication.TokenResource.revoke(Ashapi.Accounts.Token, refresh_token)
    end

    conn
    |> delete_resp_cookie("refresh_token")
    |> put_status(:ok)
    |> json(%{success: true, message: "Logged out"})
  end

  # GET /api/auth/me
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
      |> json(%{authenticated: false})
    end
  end

  # =============================================
  # Helpers
  # =============================================

  defp cookie_name do
    Application.get_env(:ashapi, :token_cookie_name, "token")
  end

  defp cookie_secure? do
    Application.get_env(:ashapi, :cookie_secure, false)
  end
end
```

### 3.6 AuthPlug — baca dari `conn.assigns[:user]`

**File:** `lib/ashapi_web/middlewares/auth_plug.ex`

`load_from_bearer` (dari AshAuthentication.Plug.Helpers) sudah verifikasi JWT dari `Authorization` header dan set `conn.assigns[:user]`. AuthPlug cukup copy ke `conn.assigns[:current_user]`:

```elixir
defmodule AshapiWeb.Plugs.AuthPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:user] do
      assign(conn, :current_user, conn.assigns[:user])
    else
      conn
    end
  end
end
```

### 3.7 Hapus TokenFromCookie

**File:** `lib/ashapi_web/middlewares/token_form_cookie.ex` — **Dihapus**

Tidak diperlukan lagi. Access token dari `Authorization` header, refresh token dari cookie langsung dibaca controller.

### 3.8 Router — update pipeline & nonaktifkan browser auth

**File:** `lib/ashapi_web/router.ex`

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug :put_secure_browser_headers
  plug AshapiWeb.Plugs.CheckOrigin
  plug :fetch_cookies
  # HAPUS: plug AshapiWeb.Plugs.TokenFromCookie
  plug :load_from_bearer
  plug :set_actor, :user
  plug AshapiWeb.Plugs.AuthPlug
end

# API routes
scope "/api", AshapiWeb do
  pipe_through [:api, :rate_limited]

  post "/auth/login", AuthController, :login
  post "/auth/logout", AuthController, :logout
  post "/auth/refresh", AuthController, :refresh   # BARU
end

scope "/api", AshapiWeb do
  pipe_through :api
  get "/auth/me", AuthController, :me
end

# JSON:API routes
scope "/api/json" do
  pipe_through [:api]

  forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
    path: "/api/json/open_api",
    default_model_expand_depth: 4

  forward "/", AshapiWeb.AshJsonApiRouter
end

# Browser — hanya landing page, auth routes dinonaktifkan
scope "/", AshapiWeb do
  pipe_through :browser

  get "/", PageController, :home

  # NONAKTIFKAN — auth pindah ke Astro
  # auth_routes AuthController, Ashapi.Accounts.User, path: "/auth"
  # sign_out_route AuthController
  # sign_in_route ...
  # reset_route ...
  # confirm_route ...
  # magic_sign_in_route ...
end
```

### 3.9 Policy — tambah untuk exchange_refresh_token

**File:** `lib/ashapi/accounts/user.ex` — di dalam blok `policies`

```elixir
# public exchange refresh token
policy action(:exchange_refresh_token) do
  authorize_if always()
end
```

### 3.10 Config

**File:** `config/dev.exs`

Tambah origin Astro dev server (4321) — sudah ada di daftar.

**File:** `config/config.exs`

Tambah konfigurasi refresh token cookie:

```elixir
config :ashapi,
  ...
  token_cookie_name: "token",
  refresh_token_cookie_name: "refresh_token",
  cookie_secure: false
```

---

## 4. Astro SSR — API Client Helper (konsep)

### File: `src/lib/api-client.ts`

```typescript
interface TokenCache {
  accessToken: string;
  expiresAt: number;
}

const tokenCache = new Map<string, TokenCache>();

function decodeJwtPayload(token: string): { exp?: number } {
  const payload = token.split('.')[1];
  return JSON.parse(atob(payload));
}

async function getAccessToken(request: Request): Promise<string | null> {
  const refreshToken = getCookie(request, 'refresh_token');
  if (!refreshToken) return null;

  const cacheKey = await hash(refreshToken);
  const cached = tokenCache.get(cacheKey);

  if (cached) {
    const payload = decodeJwtPayload(cached.accessToken);
    if (payload.exp && payload.exp > (Date.now() / 1000) + 30) {
      return cached.accessToken;
    }
  }

  return await refreshAccessToken(request, refreshToken, cacheKey);
}

async function refreshAccessToken(
  request: Request,
  refreshToken: string,
  cacheKey: string
): Promise<string | null> {
  const res = await fetch('http://phoenix:4000/api/auth/refresh', {
    method: 'POST',
    headers: {
      'Cookie': `refresh_token=${refreshToken}`,
      'Content-Type': 'application/json',
    },
  });

  if (!res.ok) {
    tokenCache.delete(cacheKey);
    return null;
  }

  const data = await res.json();
  const newRefreshToken = extractSetCookie(res, 'refresh_token');

  const payload = decodeJwtPayload(data.access_token);
  const newCacheKey = await hash(newRefreshToken ?? refreshToken);

  tokenCache.set(newCacheKey, {
    accessToken: data.access_token,
    expiresAt: payload.exp ?? 0,
  });

  if (newCacheKey !== cacheKey) tokenCache.delete(cacheKey);
  return data.access_token;
}

async function apiFetch(request: Request, path: string, init?: RequestInit) {
  const token = await getAccessToken(request);
  if (!token) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const res = await fetch(`http://phoenix:4000${path}`, {
    ...init,
    headers: {
      ...init?.headers,
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });

  return res;
}
```

---

## 5. Ringkasan File Berubah

| File | Status | Deskripsi |
|---|---|---|
| `lib/ashapi/accounts/user.ex` | ✏️ | Ubah `token_lifetime` ke 30 menit, tambah action `exchange_refresh_token`, tambah policy, modif `sign_in_with_password` |
| `lib/ashapi/accounts/user/preparations/generate_refresh_token.ex` | 🆕 | Preparation: generate refresh token JWT setelah login |
| `lib/ashapi/accounts/user/preparations/exchange_refresh_token.ex` | 🆕 | Preparation: verify + revoke + generate token pair |
| `lib/ashapi_web/controllers/auth_controller.ex` | ✏️ | Modif login/logout, tambah refresh, hapus revoke_token helper |
| `lib/ashapi_web/middlewares/auth_plug.ex` | ✏️ | Baca dari `conn.assigns[:user]` |
| `lib/ashapi_web/middlewares/token_form_cookie.ex` | ❌ | Hapus |
| `lib/ashapi_web/router.ex` | ✏️ | Tambah route refresh, hapus browser auth routes |
| `config/config.exs` | ✏️ | Tambah `refresh_token_cookie_name` |

---

## 6. Catatan Tambahan

### After-action hooks ordering
Config `read_action_after_action_hooks_in_order?: true` sudah diset di `config.exs:26`. Ini memastikan after_action hooks di `exchange_refresh_token` jalan berurutan: revoke dulu, baru generate.

### Refresh token rotation
Setiap kali `/api/auth/refresh` dipanggil:
- Refresh token lama di-revoke (tidak bisa dipakai lagi)
- Access token baru + refresh token baru di-generate
- Client menerima access token di body + refresh token baru di cookie

### Kompromi detection
Jika refresh token yang sudah di-revoke tiba-tiba dipakai lagi → `Jwt.verify` sukses (signature valid) tapi `TokenResource.revoke` gagal (token sudah di-revoke) → indikasi stolen token → force logout semua session user.

### Token cleanup
Token expired bisa dibersihkan via `expunge_expired` action atau scheduled job.

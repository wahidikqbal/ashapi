# Ashapi

**Ashapi** adalah aplikasi web modern berbasis **Phoenix 1.8.7** + **Ash Framework 3.0** yang menyediakan RESTful JSON:API untuk manajemen pengguna (autentikasi) dan blog (posts). Dibangun dengan pendekatan deklaratif Ash untuk domain-driven design, policy-based authorization, dan auto-generated API.

---

## Daftar Isi

- [Tech Stack](#tech-stack)
- [Fitur](#fitur)
- [Struktur Proyek](#struktur-proyek)
- [Architecture Overview](#architecture-overview)
- [Domain & Resources](#domain--resources)
  - [Accounts Domain](#accounts-domain)
  - [Blog Domain](#blog-domain)
- [API Endpoints](#api-endpoints)
  - [JSON:API (AshJsonApi)](#jsonapi-ashjsonapi)
  - [Custom Auth API](#custom-auth-api)
  - [Swagger / OpenAPI](#swagger--openapi)
- [Authentication & Authorization](#authentication--authorization)
- [Database](#database)
- [CORS Configuration](#cors-configuration)
- [Environment Variables](#environment-variables)
- [Setup & Development](#setup--development)
- [Production Deployment](#production-deployment)
- [Testing](#testing)
- [Mix Aliases](#mix-aliases)
- [Admin Panel](#admin-panel)
- [Monitoring](#monitoring)

---

## Tech Stack

| Teknologi | Versi | Kegunaan |
|-----------|-------|----------|
| **Elixir** | ~> 1.15 | Bahasa pemrograman |
| **Phoenix** | ~> 1.8.7 | Web framework |
| **Ash Framework** | ~> 3.0 | Domain-driven design, resources, policies |
| **AshPostgres** | ~> 2.0 | PostgreSQL data layer |
| **AshJsonApi** | ~> 1.0 | Auto-generated JSON:API |
| **AshAuthentication** | ~> 4.0 | Authentication (password, JWT, remember-me) |
| **AshAuthenticationPhoenix** | ~> 2.0 | Auth UI (LiveView) |
| **AshAdmin** | ~> 1.0 | Admin panel (dev only) |
| **Phoenix LiveView** | ~> 1.1.0 | Real-time UI |
| **PostgreSQL** | >= 16 | Database |
| **Bandit** | ~> 1.5 | HTTP server |
| **Swoosh** | ~> 1.16 | Mailer |
| **Tailwind CSS v4** | ~> 0.3 | Styling |
| **DaisyUI** | - | UI component library |
| **CORSPlug** | ~> 3.0 | CORS handling |
| **OpenApiSpex** | ~> 3.0 | OpenAPI/Swagger docs |

---

## Fitur

### Authentication & User Management
- Registrasi user dengan email & password (bcrypt hashing)
- Login dengan email & password → access token (30 menit) + refresh token (7 hari)
- Refresh token rotation — revoke lama, buat baru setiap refresh
- Logout revoke ALL tokens user (access + refresh)
- Access token only in Astro server memory (never reaches browser)
- Refresh token di HttpOnly cookie (Secure, SameSite=Strict, Path=/)
- BFF pattern: Astro SSR sebagai proxy autentikasi
- Email confirmation untuk user baru
- Password reset via email
- Change password

### Blog Posts
- CRUD posts (Create, Read, Update, Delete)
- Public read access
- Authenticated write access

### API
- Auto-generated JSON:API (JSON:API spec compliant)
- Custom JSON API endpoints untuk auth flow
- Swagger UI documentation (OpenAPI)
- CORS support dengan origin validation
- Policy-based authorization (Ash Policy)

### UI
- Phoenix LiveView pages
- Auth pages (sign-in, register, password reset, email confirm)
- DaisyUI-themed UI
- Dark/light mode toggle
- Admin panel (AshAdmin, dev only)
- LiveDashboard (dev only)

---

## Struktur Proyek

```
ashapi/
├── lib/
│   ├── ashapi.ex                          # Root module
│   ├── ashapi/
│   │   ├── application.ex                 # OTP Application
│   │   ├── repo.ex                        # AshPostgres Repo
│   │   ├── mailer.ex                      # Swoosh Mailer
│   │   ├── secrets.ex                     # AshAuthentication signing secret
│   │   ├── accounts.ex                    # Accounts Domain
│   │   ├── accounts/
│   │   │   ├── user.ex                    # User Resource
│   │   │   ├── token.ex                   # Token Resource
│   │   │   └── user/senders/
│   │   │       ├── send_new_user_confirmation_email.ex
│   │   │       └── send_password_reset_email.ex
│   │   ├── blog.ex                        # Blog Domain
│   │   └── blog/
│   │       └── post.ex                    # Post Resource
│   └── ashapi_web.ex                      # Web module entrypoint
│   └── ashapi_web/
│       ├── router.ex                      # Phoenix Router
│       ├── ash_json_api_router.ex         # AshJsonApi Router
│       ├── endpoint.ex                    # Phoenix Endpoint
│       ├── telemetry.ex                   # Telemetry metrics
│       ├── gettext.ex                     # i18n
│       ├── live_user_auth.ex              # LiveView auth hooks
│       ├── auth_overrides.ex              # Auth UI overrides
│       ├── controllers/
│       │   ├── auth_controller.ex         # Custom auth controller
│       │   ├── page_controller.ex         # Home page controller
│       │   ├── page_html.ex               # Page template
│       │   ├── error_html.ex              # HTML error pages
│       │   └── error_json.ex              # JSON error pages
│       ├── components/
│       │   ├── core_components.ex         # Reusable UI components
│       │   └── layouts.ex                 # Layout components
│       └── middlewares/
│           ├── auth_plug.ex               # JWT auth verification plug
│           ├── check_origin.ex            # CORS origin validation plug
│           └── token_form_cookie.ex       # Cookie-to-Bearer header plug
├── config/
│   ├── config.exs                         # Base config
│   ├── dev.exs                            # Development config
│   ├── prod.exs                           # Production config
│   ├── runtime.exs                        # Runtime config
│   └── test.exs                           # Test config
├── priv/
│   ├── repo/
│   │   ├── migrations/                    # Ecto migrations
│   │   └── seeds.exs                      # Seed data
│   ├── resource_snapshots/                # Ash resource snapshots
│   ├── static/                            # Static assets
│   └── gettext/                           # Translations
├── assets/
│   ├── css/app.css                        # Tailwind CSS entry
│   ├── js/app.js                          # JavaScript entry
│   ├── vendor/                            # Vendor scripts (heroicons, daisyUI, topbar)
│   └── tsconfig.json
├── test/                                  # Tests
├── document/                              # Documentation files
│   ├── AGENTS.md
│   ├── ENDPOINTS.md
│   ├── CORS_SETUP.md
│   └── CORS_TESTING.md
├── mix.exs
└── .env.example
```

---

## Architecture Overview

### Flow Request API

```
Astro SSR (BFF) — semua request dari browser melalui Astro
       │
       │  Authorization: Bearer <access_token> (set by Astro)
       │  Cookie: refresh_token (forward by Astro jika perlu)
       ▼
  Phoenix Endpoint
       │
       ├── CORSPlug (validasi origin)
       ├── Plug.Parsers (termasuk AshJsonApi.Plug.Parser)
       └── Plug.Session
            │
            ▼
       Router (lib/ashapi_web/router.ex)
            │
            ├── API Pipeline (:api)
            │   ├── CheckOrigin plug (optional — trusting Astro proxy)
            │   ├── load_from_bearer (verify access_token, purpose="user")
            │   ├── set_actor (Ash actor)
            │   └── AuthPlug (copy assigns[:user] → :current_user)
            │
            ├── Scope /api/auth → AuthController (custom JSON)
            ├── Scope /api/json → AshJsonApiRouter (auto-generated)
            └── Scope / (browser) → LiveView pages
               (auth routes redirect to / — use Astro instead)
```

### Ash Domain Flow

```
Ash Domain (Accounts/Blog)
    │
    ├── Resource (User/Token/Post)
    │   ├── DataLayer (AshPostgres → PostgreSQL)
    │   ├── Actions (CRUD + custom)
    │   ├── Policies (authorization rules)
    │   └── Extensions (Auth, JsonApi)
    │
    └── Auto-generated by AshJsonApi
        └── JSON:API compliant endpoints
```

---

## Domain & Resources

### Accounts Domain

**Module:** `Ashapi.Accounts`

Domain untuk manajemen pengguna dan autentikasi.

#### User Resource (`Ashapi.Accounts.User`)

| Attribute | Type | Constraints |
|-----------|------|-------------|
| `id` | UUID (primary key) | Auto-generated |
| `email` | `:ci_string` | Not null, unique, regex validated |
| `hashed_password` | `:string` | Not null, sensitive |
| `confirmed_at` | `:utc_datetime_usec` | Nullable |

**Identities:** `unique_email` pada field `email`

**Authentication Strategies:**
- **Password** (`:password`) — login dengan email + password, bcrypt hashing, JWT tokens
- **Remember Me** (`:remember_me`) — persistent session

**Add-ons:**
- **Confirmation** (`:confirm_new_user`) — konfirmasi email via link
- **Log Out Everywhere** — revoke all tokens saat password diubah

**Actions:**
| Action | Type | Deskripsi |
|--------|------|-----------|
| `get_by_subject` | Read | Get user by JWT subject claim |
| `change_password` | Update | Change password (dengan current password) |
| `sign_in_with_password` | Read | Login dengan email + password → JWT |
| `sign_in_with_token` | Read | Exchange short-lived token → JWT |
| `register_with_password` | Create | Register user baru |
| `request_password_reset_token` | Action | Kirim email reset password |
| `get_by_email` | Read | Lookup user by email |
| `reset_password_with_token` | Update | Reset password dengan token |

**Policies:**
- Bypass: AshAuthentication interactions (selalu allow)
- `change_password`: hanya user sendiri
- `register_with_password`: public
- `sign_in_with_password`: public

#### Token Resource (`Ashapi.Accounts.Token`)

**Module:** `Ashapi.Accounts.Token`

Token storage untuk JWT authentication.

| Attribute | Type | Notes |
|-----------|------|-------|
| `jti` | String (PK) | JWT ID, primary key |
| `subject` | String | User subject claim |
| `expires_at` | UTC DateTime | Token expiration |
| `purpose` | String | Token purpose |
| `extra_data` | Map | Additional data |
| `created_at` | Timestamp | Auto |
| `updated_at` | Timestamp | Auto |

**Actions:** expired, get_token, revoked?, revoke_token, revoke_jti, store_token, expunge_expired, revoke_all_stored_for_subject

---

### Blog Domain

**Module:** `Ashapi.Blog`

Domain untuk blog posts.

#### Post Resource (`Ashapi.Blog.Post`)

| Attribute | Type | Constraints |
|-----------|------|-------------|
| `id` | UUID (primary key) | Auto-generated |
| `title` | String | Not null, public |
| `content` | String | Public |
| `inserted_at` | Timestamp | Auto (timestamps) |
| `updated_at` | Timestamp | Auto (timestamps) |

**Actions:** read, index, create, update, destroy

**Policies:**
- Read: public (semua orang bisa baca)
- Create/Update/Destroy: harus login (`actor_present?`)

---

## API Endpoints

### JSON:API (AshJsonApi)

**Base URL:** `/api/json`

Auto-generated JSON:API compliant endpoints. Format request/response mengikuti spesifikasi JSON:API (media type `application/vnd.api+json`).

#### Users

| Method | Endpoint | Deskripsi | Auth |
|--------|----------|-----------|------|
| `GET` | `/api/json/users` | List all users | Optional |
| `GET` | `/api/json/users/:id` | Get user by ID | Optional |
| `POST` | `/api/json/users/register` | Register user baru | Public |
| `POST` | `/api/json/users/sign-in` | Sign in (untuk Swagger testing) | Public |

**Request Body (Register):**
```json
{
  "user": {
    "email": "user@example.com",
    "password": "password123"
  }
}
```

**Response (Register):**
```json
{
  "data": {
    "id": "uuid",
    "type": "user",
    "attributes": { "email": "user@example.com" },
    "metadata": { "token": "jwt_token_here" }
  }
}
```

#### Posts

| Method | Endpoint | Deskripsi | Auth |
|--------|----------|-----------|------|
| `GET` | `/api/json/posts` | List all posts | Public |
| `GET` | `/api/json/posts/:id` | Get post by ID | Public |
| `POST` | `/api/json/posts` | Create new post | Required |
| `PATCH` | `/api/json/posts/:id` | Update post | Required |
| `DELETE` | `/api/json/posts/:id` | Delete post | Required |

**Request Body (Create Post):**
```json
{
  "post": {
    "title": "Judul Post",
    "content": "Konten post"
  }
}
```

---

### Custom Auth API

**Base URL:** `/api/auth`

#### POST `/api/auth/login`

Login dengan email & password. **Hanya boleh dipanggil oleh Astro BFF** (internal), bukan langsung dari browser.

**Request:**
```json
{
  "data": {
    "attributes": {
      "email": "user@example.com",
      "password": "password123"
    }
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "message": "You are now signed in"
}
```
**Set-Cookie:** `refresh_token=<JWT>; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=604800`

**Catatan Astro:** Ambil `access_token` dari body → simpan di cache. **Jangan forward `access_token` ke browser.** Forward hanya `Set-Cookie`.

**Response (401):**
```json
{
  "success": false,
  "error": "Incorrect email or password"
}
```

#### POST `/api/auth/refresh`

Menukar refresh token dengan access token baru (refresh token rotation).

**Cookie yang dikirim:** `refresh_token=<JWT>` (dikirim otomatis oleh browser via Astro)

**Response (200):**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs..."
}
```
**Set-Cookie:** `refresh_token=<JWT baru>; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=604800` (refresh token rotation — token lama sudah tidak valid)

**Response (401):**
```json
{
  "error": "Invalid or expired refresh token"
}
```
**Set-Cookie:** `refresh_token=; Path=/; Max-Age=0` (cookie dihapus)

#### POST `/api/auth/logout`

Logout dan revoke semua token user (access + refresh).

**Header yang dikirim:** `Authorization: Bearer <access_token>`

**Response (200):**
```json
{
  "success": true,
  "message": "Logged out"
}
```
**Set-Cookie:** `refresh_token=; Path=/; Max-Age=0` (cookie dihapus)

#### GET `/api/auth/me`

Get current authenticated user.

**Header yang dikirim:** `Authorization: Bearer <access_token>`

**Response (terautentikasi - 200):**
```json
{
  "authenticated": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

**Response (tidak terautentikasi - 401):**
```json
{
  "authenticated": false
}
```

---

### Browser Auth Routes (LiveView — Terdepresiasi)

Auth LiveView routes dinonaktifkan. Semua autentikasi dipindahkan ke Astro SSR (BFF).

| Route | Status | Deskripsi |
|-------|--------|-----------|
| `/` | Aktif | Home page |
| `/auth/sign-in` | ❌ Redirect ke `/` | Pindah ke Astro |
| `/auth/register` | ❌ Redirect ke `/` | Pindah ke Astro |
| `/auth/reset` | ❌ Redirect ke `/` | Pindah ke Astro |
| `/auth/confirm` | Aktif | Email confirmation page |
| `/auth/logout` | ❌ Redirect ke `/` | Pindah ke Astro |

### Swagger / OpenAPI

**URL:** `/api/json/swaggerui`

Dokumentasi API interaktif berbasis OpenAPI (via OpenApiSpex). Swagger UI otomatis tergenerate dari definisi AshJsonApi resources.

---

## Authentication & Authorization

### Arsitektur Auth (BFF Pattern)

**Ashapi** menggunakan **Backend-for-Frontend (BFF)** pattern dengan **Astro SSR** sebagai BFF dan **Phoenix** sebagai API backend. Authentication menggunakan dual-token (access + refresh token).

```
┌─────────────────────────────────────────────────────────────────┐
│                        Browser (User)                           │
│                                                                 │
│  Cookie: refresh_token (HttpOnly, Secure, SameSite=Strict)      │
│                                                                 │
│  Client-side fetch → /astro/api/auth/* (Astro BFF)              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Astro SSR (BFF Layer)                            │
│                                                                 │
│  - In-memory cache untuk access_token                           │
│  - Decode JWT → cek exp → refresh jika expired (buffer 30dtk)  │
│  - Proxy semua API call ke Phoenix                              │
│  - Filter access_token dari response sebelum ke browser         │
│  - Forward Set-Cookie refresh_token ke browser                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │  Authorization: Bearer <access_token>
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Phoenix API (ashapi)                            │
│                                                                 │
│  - Verify access token (JWT, 30 menit, purpose: "user")         │
│  - Refresh endpoint → validasi + rotation refresh token (7 hari)│
│  - Revoke token di database saat logout                         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PostgreSQL                                   │
│                                                                  │
│  tokens table:                                                   │
│  - access token (purpose="user", expires_at=+30m)               │
│  - refresh token (purpose="user", expires_at=+7d)               │
│  - revocation records (purpose="revocation")                    │
└─────────────────────────────────────────────────────────────────┘
```

### Token Flow

| Token | Lokasi | Umur | Disimpan di DB? | Fungsi |
|---|---|---|---|---|
| **Access Token** | In-memory cache Astro server | 30 menit | Ya (purpose="user") | Autentikasi setiap API call ke Phoenix |
| **Refresh Token** | HttpOnly cookie browser | 7 hari | Ya (purpose="user") | Mendapatkan access token baru via rotation |

**Access token tidak pernah sampai ke browser** — hanya Astro server yang memegangnya.

---

### 1. Login Flow

```
Browser                          Astro SSR (BFF)                          Phoenix
  │                                │                                        │
  │  LoginForm.svelte              │                                        │
  │  fetch('/astro/api/auth/       │                                        │
  │    login', POST)               │                                        │
  │  {email, password} ───────────►│                                        │
  │                                │                                        │
  │                                ├─ POST /api/auth/login ───────────────►│
  │                                │  {data: {attributes: {email, password}}}│
  │                                │                                        │
  │                                │                                        ├─ sign_in_with_password
  │                                │                                        ├─ Generate ACCESS TOKEN (JWT, 30 menit)
  │                                │                                        │  → purpose: "user", jti, sub: "user?id=..."
  │                                │                                        │  → INSERT INTO tokens
  │                                │                                        ├─ Generate REFRESH TOKEN (JWT, 7 hari)
  │                                │                                        │  → INSERT INTO tokens
  │                                │                                        │
  │                                │  ◄── {access_token, message, ...} +   │
  │                                │        Set-Cookie: refresh_token=...   │
  │                                │                                        │
  │                                ├─ 1. Simpan access_token di cache      │
  │                                ├─ 2. FILTER response: HAPUS access_token│
  │                                ├─ 3. Forward Set-Cookie refresh_token   │
  │                                │                                        │
  │  ◄── {success, message} +     │                                        │
  │       Set-Cookie: refresh_token│                                        │
```

### 2. Data Request Flow (SSR — misal dashboard)

```
Browser                          Astro SSR (BFF)                          Phoenix
  │                                │                                        │
  │  GET /dashboard                │                                        │
  │  Cookie: refresh_token=... ───►│                                        │
  │                                │                                        │
  │                                ├─ getAccessToken(request):              │
  │                                │  1. Baca refresh_token dari cookie     │
  │                                │  2. Cek cache by hash(refresh_token)   │
  │                                │                                        │
  │                                ├─ Cache VALID (exp > 30dtk buffer):    │
  │                                │  → pakai access_token                  │
  │                                │                                        │
  │                                ├─ Cache EXPIRED/TIDAK ADA:             │
  │                                │  → refresh (lihat flow #3)             │
  │                                │                                        │
  │                                ├─ apiFetch(GET /api/json/posts):        │
  │                                │  GET /api/json/posts ─────────────────►│
  │                                │  Authorization: Bearer <access_token>  │
  │                                │                                        │
  │                                │                                        ├─ load_from_bearer:
  │                                │                                        │  Validasi access_token (purpose="user")
  │                                │                                        │  → conn.assigns[:user]
  │                                │                                        │
  │                                │  ◄── data ────────────────────────────│
  │                                │                                        │
  │  ◄── HTML rendered +          │                                        │
  │       Set-Cookie (jika ada    │                                        │
  │       refresh token rotation) │                                        │
```

### 3. Refresh Token Rotation

```
Astro SSR                                                                 Phoenix
  │                                                                         │
  ├─ refreshAccessToken():                                                  │
  │  cache expired / tidak ada                                              │
  │                                                                         │
  │  POST /api/auth/refresh ───────────────────────────────────────────────►│
  │  Cookie: refresh_token=<old>  (forward dari cookie browser)             │
  │                                                                         │
  │                                                                         ├─ exchange_refresh_token action:
  │                                                                         │  1. Verify JWT refresh token
  │                                                                         │  2. revoke_jti (purpose → "revocation")
  │                                                                         │  3. Generate access_token BARU (30m)
  │                                                                         │  4. Generate refresh_token BARU (7d)
  │                                                                         │     → INSERT INTO tokens
  │                                                                         │
  │  ◄── {access_token} +                                                   │
  │       Set-Cookie: refresh_token=<new>                                   │
  │                                                                         │
  ├─ Simpan access_token di cache (key: hash(new_refresh_token))            │
  ├─ Hapus cache key lama                                                   │
  ├─ Forward Set-Cookie refresh_token baru ke browser                       │
```

### 4. Logout Flow

```
Browser                          Astro SSR (BFF)                          Phoenix
  │                                │                                        │
  │  LogoutPage.svelte             │                                        │
  │  fetch('/astro/api/auth/       │                                        │
  │    logout', POST) ────────────►│                                        │
  │  Cookie: refresh_token=...     │                                        │
  │                                │                                        │
  │                                ├─ resolveAccessToken(request):          │
  │                                │  → access_token dari cache             │
  │                                │                                        │
  │                                ├─ POST /api/auth/logout ──────────────►│
  │                                │  Authorization: Bearer <access_token>  │
  │                                │                                        │
  │                                │                                        ├─ load_from_bearer:
  │                                │                                        │  validasi access_token
  │                                │                                        │  → conn.assigns[:current_user]
  │                                │                                        │
  │                                │                                        ├─ revoke_all_tokens_for_subject:
  │                                │                                        │  subject = "user?id=#{user.id}"
  │                                │                                        │  SELECT * FROM tokens WHERE subject = "..."
  │                                │                                        │  → UPDATE purpose="revocation" utk SETIAP token
  │                                │                                        │
  │                                │  ◄── 200 {success, message} +         │
  │                                │       Set-Cookie: hapus refresh_token  │
  │                                │                                        │
  │                                ├─ deleteCachedToken(hash(refresh_token))│
  │                                ├─ Forward Set-Cookie hapus ke browser   │
  │                                │                                        │
  │  ◄── 200 + Cookie refresh_token dihapus                                │
  │                                │                                        │
  │  → Redirect ke /auth/login    │                                        │
```

---

### Token Configuration

| Parameter | Value |
|-----------|-------|
| **Access token lifetime** | 30 menit |
| **Refresh token lifetime** | 7 hari |
| **Refresh token rotation** | Ya — setiap refresh revoke lama, buat baru |
| **Buffer refresh** | 30 detik sebelum expired (Astro side) |
| **Cookie name (dev)** | `refresh_token_dev` |
| **Cookie name (prod)** | `refresh_token` |
| **Cookie path** | `/` |
| **Cookie flags** | HttpOnly, Secure (prod), SameSite=Strict |

### Middleware Chain (API Pipeline)

1. **CheckOrigin** — Validasi Origin header terhadap whitelist
2. **load_from_bearer** — Load user dari Bearer token (access_token dengan purpose "user")
3. **set_actor** — Set Ash actor untuk policy evaluation
4. **AuthPlug** — Copy `conn.assigns[:user]` → `conn.assigns[:current_user]`

### Authorization Policies (Ash Policy)

**User:**
- Auth interactions: bypass (always allowed)
- Change password: hanya user sendiri
- Register: public
- Sign in: public
- `exchange_refresh_token`: public (dengan refresh token yang valid)

**Token:**
- `revoke_all_stored_for_subject`: always allowed
- read/update: always allowed

**Post:**
- Read: public (semua orang)
- Create/Update/Delete: harus login (`actor_present?`)

---

## Database

### PostgreSQL >= 16

**Extensions yang digunakan:**
- `ash-functions` — Ash framework functions
- `citext` — Case-insensitive text (untuk email)

### Migrations

File migrasi ada di `priv/repo/migrations/`:
- `*_extensions_1.exs` — Setup database extensions
- `*_auth.exs` — Auth tables (users, tokens)
- `*_migrate_resources1_dev.exs` — Blog posts table

### Reset Database

```bash
mix ecto.reset
```

---

## CORS Configuration

CORS dikonfigurasi secara environment-aware.

### Development

Origin yang diizinkan (default di `config/dev.exs`):
- `http://localhost:3000`
- `http://localhost:5173`
- `http://localhost:5174`
- `http://127.0.0.1:3000`, `5173`, `5174`

### Production

Set environment variable `CORS_ALLOWED_ORIGINS`:
```bash
export CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com
```

### CORSPlug Configuration (di `endpoint.ex`)

```elixir
plug CORSPlug,
  origin: allowed_origins,
  credentials: true,
  methods: ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  headers: ["Content-Type", "Authorization", "Accept", "X-Requested-With"]
```

### Security Layers

1. **CORSPlug** — Origin validation
2. **CheckOrigin plug** — Additional origin validation untuk API
3. **HttpOnly cookie** — Mencegah XSS
4. **SameSite=Lax/Strict** — CSRF protection
5. **Secure cookie** — Hanya via HTTPS (production)

---

## Environment Variables

| Variable | Required | Default | Deskripsi |
|----------|----------|---------|-----------|
| `DATABASE_URL` | Prod | - | PostgreSQL connection URL |
| `PORT` | No | `4000` | Server port |
| `PHX_HOST` | Prod | - | Server hostname |
| `SECRET_KEY_BASE` | Prod | - | Phoenix session signing secret |
| `TOKEN_SIGNING_SECRET` | Prod | - | JWT signing secret |
| `CORS_ALLOWED_ORIGINS` | Prod | - | Comma-separated allowed CORS origins |
| `POOL_SIZE` | No | `10` | Database pool size |
| `DNS_CLUSTER_QUERY` | No | - | DNS cluster query |
| `ECTO_IPV6` | No | - | Enable IPv6 for Ecto |

### Setup `.env` untuk Development

```bash
cp .env.example .env
# Edit .env sesuai kebutuhan
```

---

## Setup & Development

### Prerequisites

- Elixir ~> 1.15
- PostgreSQL >= 16
- Node.js (untuk assets)

### Setup Awal

```bash
# Clone & masuk direktori
git clone <repo-url>
cd ashapi

# Install dependencies, setup database, build assets
mix setup

# Jalankan server
mix phx.server
```

Buka `http://localhost:4000` di browser.

### Setup Langkah Demi Langkah

```bash
# 1. Get dependencies
mix deps.get

# 2. Setup Ash (database, migrations)
mix ash.setup

# 3. Setup assets (Tailwind, esbuild)
mix assets.setup

# 4. Build assets
mix assets.build

# 5. Run seeds
mix run priv/repo/seeds.exs

# 6. Start server
mix phx.server
```

### Development Server

```bash
# Standard
mix phx.server

# With IEx interactive shell
iex -S mix phx.server
```

---

## Production Deployment

### Build

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

### Runtime Configuration

Set environment variables yang required:
```bash
export DATABASE_URL=ecto://user:pass@host/prod_db
export SECRET_KEY_BASE=<generated_secret>
export TOKEN_SIGNING_SECRET=<generated_secret>
export PHX_HOST=example.com
export CORS_ALLOWED_ORIGINS=https://example.com
```

### Generate Secrets

```bash
mix phx.gen.secret
```

### Production Checklist

- [ ] Set `token_lifetime` ke `{24, :hours}` atau sesuai kebutuhan
- [ ] Set `SECURE_COOKIE=true` (secure cookie hanya via HTTPS)
- [ ] Set `CORS_ALLOWED_ORIGINS` dengan domain produksi
- [ ] Jangan gunakan wildcard CORS dengan credentials
- [ ] Gunakan HTTPS
- [ ] Set `POOL_SIZE` sesuai kapasitas database

---

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/ashapi_web/controllers/page_controller_test.exs

# Run with coverage
mix test --cover

# Run precommit checks (compile + warnings + format + test)
mix precommit
```

### Test Files

- `test/support/data_case.ex` — Data test helpers
- `test/support/conn_case.ex` — Connection test helpers
- `test/ashapi_web/controllers/page_controller_test.exs`
- `test/ashapi_web/controllers/error_html_test.exs`
- `test/ashapi_web/controllers/error_json_test.exs`

---

## Mix Aliases

| Alias | Perintah |
|-------|----------|
| `mix setup` | Install deps, setup DB, build assets, run seeds |
| `mix ecto.setup` | Create DB, run migrations, run seeds |
| `mix ecto.reset` | Drop DB, run ecto.setup |
| `mix test` | Setup Ash, run tests |
| `mix assets.setup` | Install Tailwind + esbuild |
| `mix assets.build` | Compile, build Tailwind + esbuild |
| `mix assets.deploy` | Build minified assets + digest |
| `mix precommit` | Compile (warnings as errors), check unused deps, format, test |

---

## Admin Panel

**URL (development only):** `/admin`

AshAdmin menyediakan antarmuka admin untuk:
- Melihat dan mengelola resources (Users, Tokens, Posts)
- Menjalankan actions
- Melihat data relationships
- Policy breakdown viewer

Aktif hanya ketika `dev_routes: true` (development).

---

## Monitoring

### LiveDashboard

**URL (development only):** `/dev/dashboard`

Metrics yang dimonitor:
- **Phoenix:** Request count, duration, stop/exception
- **Router:** Dispatch count, duration, exception
- **Channel:** Subscribed/unsubscribed
- **Database:** Query total, decode, query, queue, idle time
- **VM:** Memory, run queue length

### Mailbox Preview

**URL (development only):** `/dev/mailbox`

Preview email yang dikirim via Swoosh (development).

---

## Keamanan

### Cookie Security
- **Refresh token** di HttpOnly cookie, tidak bisa diakses JavaScript
- `SameSite: "Strict"` — CSRF protection
- `Secure: true` di production — Hanya via HTTPS
- `Path: /` — Agar middleware Astro bisa baca di semua halaman SSR
- Nama cookie per environment: `refresh_token_dev` (dev), `refresh_token` (prod)

### Token Security
- **Access token** hanya di in-memory cache Astro server — tidak pernah ke browser
- **Refresh token** di HttpOnly cookie + disimpan di database
- JWT ditandatangani dengan signing secret
- Refresh token rotation: setiap refresh revoke lama, buat baru
- Logout revoke ALL tokens (access + refresh) untuk user
- Token lifetime: access 30 menit, refresh 7 hari
- Buffer 30 detik sebelum expired — hindari race condition concurrent requests

### CORS Security
- Origin whitelist (bukan wildcard)
- Credentials hanya diizinkan dengan specific origins
- Dual validation: CORSPlug + CheckOrigin plug
- Preflight caching (24 jam)

### Password Security
- Bcrypt hashing (via `bcrypt_elixir`)
- Password confirmation validation
- Minimum 8 karakter

---

## Dokumentasi Tambahan

Dokumentasi lebih detail ada di folder `document/`:
- `document/ENDPOINTS.md` — Detail endpoint dan contoh curl
- `document/CORS_SETUP.md` — Setup CORS lengkap
- `document/CORS_TESTING.md` — Cara test CORS
- `document/AGENTS.md` — Guidelines untuk AI coding assistant

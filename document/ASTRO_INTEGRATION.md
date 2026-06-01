# Integrasi Astro ↔ Phoenix — Auth dengan Access + Refresh Token

Dokumen ini berisi spesifikasi API dan panduan implementasi untuk frontend Astro (SSR/BFF).

---

## 1. Arsitektur

```
Browser (user)
  │  Cookie: refresh_token (HttpOnly, Secure, SameSite=Strict, Path=/)
  ▼
Astro SSR (BFF)
  │  Cache access_token di server memory
  │  Decode JWT → cek exp → refresh jika expired
  ▼
Phoenix API (ashapi)
  │  Verify access token (JWT, 30 menit)
  │  Refresh endpoint → validasi + rotation refresh token (7 hari)
  ▼
PostgreSQL
```

### Aturan Penting

| Token | Lokasi | Lifetime | Siapa yang punya akses |
|---|---|---|---|
| **Access token** | In-memory cache di Astro server | 30 menit | Hanya Astro server |
| **Refresh token** | HttpOnly cookie di browser | 7 hari | Browser (dikirim otomatis) + Astro server (dibaca dari cookie) |

**Access token TIDAK BOLEH sampai ke browser.** Hanya Astro server yang menyimpannya.

---

## 2. Endpoint API

Base URL: `http://phoenix:4000/api`

### POST /api/auth/login

Authentikasi user dengan email & password.

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

**Response 200:**
```json
{
  "success": true,
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "message": "You are now signed in"
}
```
**Set-Cookie:** `refresh_token=<JWT>; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=604800`

**Response 401:**
```json
{
  "success": false,
  "error": "Incorrect email or password"
}
```

**Implementasi di Astro:**
- Forward request dari browser ke Phoenix `POST /api/auth/login`
- Ambil `access_token` dari response body → simpan di in-memory cache
- Forward `Set-Cookie` header untuk `refresh_token` ke browser (Astro jangan simpan refresh token)

---

### POST /api/auth/refresh

Menukar refresh token dengan access token baru (refresh token rotation).

**Cookie yang dikirim:** `refresh_token=<JWT>` (dikirim otomatis oleh browser)

**Response 200:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs..."
}
```
**Set-Cookie:** `refresh_token=<JWT baru>; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=604800` (refresh token rotation — token lama sudah tidak valid)

**Response 401:**
```json
{
  "error": "Invalid or expired refresh token"
}
```
**Set-Cookie:** `refresh_token=; Path=/; Max-Age=0` (cookie dihapus)

**Implementasi di Astro (kritis):**
- Panggil endpoint ini KETIKA access token expired atau tidak ada di cache
- Forward cookie `refresh_token` dari request browser ke Phoenix
- Simpan `access_token` baru di cache
- Forward `Set-Cookie` untuk `refresh_token` baru ke browser

---

### POST /api/auth/logout

Revoke refresh token dan hapus cookie.

**Cookie yang dikirim:** `refresh_token=<JWT>` (opsional — boleh tanpa cookie)

**Response 200:**
```json
{
  "success": true,
  "message": "Logged out"
}
```
**Set-Cookie:** `refresh_token=; Path=/; Max-Age=0` (cookie dihapus)

**Implementasi di Astro:**
- Forward request dari browser ke Phoenix
- Forward `Set-Cookie` response ke browser (hapus cookie)
- Hapus access token dari cache

---

### GET /api/auth/me

Mendapatkan informasi user yang sedang login.

**Header:**
```
Authorization: Bearer <access_token>
```

**Response 200 (terautentikasi):**
```json
{
  "authenticated": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

**Response 401 (tidak terautentikasi):**
```json
{
  "authenticated": false
}
```

---

## 3. API Client Helper — Konsep Implementasi

### Pseudocode untuk Astro SSR

```typescript
// Cache in-memory di Astro server
const tokenCache = new Map<string, { accessToken: string; expiresAt: number }>();

// Helper: decode JWT payload (hanya baca exp, TANPA verifikasi)
function decodeJwtPayload(token: string): { exp?: number } {
  const payload = token.split('.')[1];
  return JSON.parse(atob(payload));
}

// Fungsi utama: dapatkan access token untuk API call
async function getAccessToken(request: Request): Promise<string | null> {
  // 1. Baca refresh_token dari cookie request browser
  const refreshToken = getCookie(request, 'refresh_token');
  if (!refreshToken) return null;

  // 2. Cek cache
  const cacheKey = await hash(refreshToken);
  const cached = tokenCache.get(cacheKey);

  if (cached) {
    // Decode JWT untuk dapat exp (tanpa verifikasi — cukup baca payload)
    const payload = decodeJwtPayload(cached.accessToken);
    // Buffer 30 detik sebelum expired — hindari race condition
    if (payload.exp && payload.exp > (Date.now() / 1000) + 30) {
      return cached.accessToken;  // Masih valid
    }
  }

  // 3. Access token expired/tidak ada → refresh
  return await refreshAccessToken(request, refreshToken, cacheKey);
}

// Refresh: call Phoenix, update cache
async function refreshAccessToken(
  request: Request,
  refreshToken: string,
  oldCacheKey: string
): Promise<string | null> {
  const res = await fetch('http://phoenix:4000/api/auth/refresh', {
    method: 'POST',
    headers: {
      'Cookie': `refresh_token=${refreshToken}`,
      'Content-Type': 'application/json',
    },
  });

  if (!res.ok) {
    tokenCache.delete(oldCacheKey);
    return null;
  }

  const data = await res.json();
  const newRefreshToken = extractSetCookie(res, 'refresh_token');

  // Cache key berubah karena refresh token rotation
  const payload = decodeJwtPayload(data.access_token);
  const newCacheKey = await hash(newRefreshToken ?? refreshToken);

  tokenCache.set(newCacheKey, {
    accessToken: data.access_token,
    expiresAt: payload.exp ?? 0,
  });

  // Hapus cache key lama
  if (newCacheKey !== oldCacheKey) tokenCache.delete(oldCacheKey);

  return data.access_token;
}

// Proxy fetch: otomatis attach access token
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

### Key Points untuk Developer Astro

| Poin | Penjelasan |
|---|---|
| **Cache key** | Gunakan hash dari refresh token. Setiap rotation → cache key baru. Cache lama otomatis tidak terpakai. |
| **Buffer 30 detik** | Jangan tunggu sampai exact expired. Cek 30 detik sebelum expired untuk antisipasi race condition. |
| **Cookie forwarding** | Refresh token cookie harus di-forward dari request browser ke Phoenix. Jangan simpan refresh token di Astro. |
| **Set-Cookie forwarding** | Response Set-Cookie dari Phoenix (refresh token baru / hapus cookie) harus di-forward ke browser. |
| **Access token storage** | Simpan di in-memory Map. Tidak perlu di-disk. Hilang saat server restart tidak masalah (akan di-refresh ulang). |
| **Scaling** | In-memory cache tidak scale horizontal. Untuk multi-instance: gunakan Redis. |

---

## 4. Alur Per Halaman (SSR)

Setiap SSR request yang butuh data dari API:

```
1. Browser request halaman → Astro SSR handler
2. Astro baca cookie refresh_token dari request
3. Astro panggil getAccessToken(request):
   a. Cek cache → jika ada & belum expired → pakai
   b. Jika expired/tidak ada → call /api/auth/refresh
4. Astro call API Phoenix dengan Authorization: Bearer <access_token>
5. Astro render HTML + kirim ke browser
   (termasuk Set-Cookie dari refresh token jika ada rotation)
```

---

## 5. Catatan Penting

### Cookie Path
Cookie refresh_token diset dengan `Path=/` agar bisa dibaca middleware Astro di semua halaman SSR (termasuk non-API paths seperti `/user/dashboard`). Aman karena:
- **HttpOnly** — tidak bisa dibaca JavaScript
- **SameSite=Strict** — hanya dikirim untuk same-site requests
- Value adalah **refresh token JWT** — tidak berguna untuk path non-API (hanya bisa ditukar di `/api/auth/refresh`)

### Cookie Name per Environment
Nama cookie refresh_token berbeda antar environment untuk mencegah bentrok:

| Environment | Nama Cookie |
|---|---|
| Development | `refresh_token_dev` |
| Production | `refresh_token` |

Pastikan Astro menggunakan nama cookie yang sesuai dengan environment saat membaca dari request (`getCookie(request, 'refresh_token_dev')` atau `getCookie(request, 'refresh_token')`). Bisa gunakan environment variable `PUBLIC_REFRESH_TOKEN_COOKIE_NAME`.

### Refresh Token Rotation
Setiap kali refresh dipanggil:
- Refresh token **lama di-revoke** (tidak bisa dipakai lagi)
- Refresh token **baru dibuat** dan dikirim via Set-Cookie
- Jika refresh token yang sudah di-revoke dipakai lagi → indikasi kompromi → semua session user di-revoke

### Logout
Saat logout:
1. Panggil `POST /api/auth/logout`
2. Response akan menghapus cookie `refresh_token`
3. Hapus access token dari cache Astro
4. Redirect user ke halaman login

### Error Handling
- **401 dari `/api/auth/refresh`**: Cookie invalid/expired → redirect ke halaman login, pastikan cookie sudah terhapus
- **401 dari API call lain**: Coba refresh satu kali. Jika masih 401 → redirect ke login
- **Network error**: Jangan hapus cache — mungkin temporary issue

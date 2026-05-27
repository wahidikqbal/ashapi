# CORS Testing Guide

## Quick Setup

### 1. Copy `.env.example` ke `.env`

```bash
cp .env.example .env
```

### 2. Edit `.env` dengan nilai yang sesuai

Untuk development, nilai default sudah cukup:

```bash
# Database Configuration
DATABASE_URL=ecto://postgres:postgres@localhost:5432/ashapi_dev

# Server Configuration
PORT=4000
PHX_HOST=localhost:4000

# Secrets (Generate dengan: mix phx.gen.secret)
SECRET_KEY_BASE=your-secret-key-base-here
TOKEN_SIGNING_SECRET=your-token-signing-secret-here

# CORS Configuration
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:5174
```

---

## Testing CORS Configuration

Ada 3 cara untuk test apakah CORS sudah berjalan:

### ✅ Cara 1: Browser GUI Testing (Paling Mudah)

1. Buka file `test_cors.html` di browser:
   ```bash
   # Gunakan file:// atau web server
   # Atau copy path file ke browser address bar
   file:///home/ikqbal/project/elixir/ashapi/test_cors.html
   ```

2. Pastikan Backend URL: `http://localhost:4000`

3. Klik "Run Test" untuk masing-masing test case

4. Lihat hasilnya:
   - ✅ = CORS berfungsi
   - ❌ = CORS tidak berfungsi

**Hasil yang diharapkan:**
```
Test 1: Preflight (OPTIONS) ✅
Test 2: Simple GET ✅
Test 3: With Credentials ✅
Test 4: Wrong Origin ✅ (rejected)
Test 5: POST Request ✅
```

---

### ✅ Cara 2: Curl Testing (Terminal)

Project Anda punya 2 endpoint untuk testing:
- **`users`** - `/api/json/users` (authentication resource)
- **`posts`** - `/api/json/posts` (blog resource)

1. Jalankan script test dengan endpoint pilihan:

```bash
chmod +x test_cors.sh

# Test users endpoint (default)
./test_cors.sh users

# Test posts endpoint
./test_cors.sh posts

# Default (same as users)
./test_cors.sh
```

2. Atau manual test dengan curl:

**Preflight request (posts endpoint):**
```bash
curl -v -X OPTIONS "http://localhost:4000/api/json/posts" \
  -H "Origin: http://localhost:5173" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: Content-Type"
```

**Harus lihat di response:**
```
< HTTP/1.1 204 No Content
< Access-Control-Allow-Origin: http://localhost:5173
< Access-Control-Allow-Methods: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS
< Access-Control-Allow-Headers: Content-Type, Authorization, Accept, X-Requested-With
< Access-Control-Allow-Credentials: true
```

**Simple GET request (users endpoint):**
```bash
curl -i -X GET "http://localhost:4000/api/json/users" \
  -H "Origin: http://localhost:5173"
```

**Dengan cookies (posts endpoint):**
```bash
curl -i -X GET "http://localhost:4000/api/json/users" \
  -H "Origin: http://localhost:5173" \
  -H "Cookie: token=dummy_token"
```

---

### ✅ Cara 3: Browser DevTools (Paling Detail)

1. Buka frontend app di browser (misalnya `http://localhost:5173`)

2. Buka Developer Tools: **F12** → tab **Network**

3. Lakukan request API ke backend (misalnya fetch user list)

4. Lihat Network tab, cari request ke backend

5. Klik request, lihat tab **Response Headers** mencari:
   ```
   Access-Control-Allow-Origin: http://localhost:5173
   Access-Control-Allow-Credentials: true
   Access-Control-Allow-Methods: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS
   ```

6. Jika ada error CORS, akan muncul di **Console** tab (merah)

---

## Environment Variables untuk Production

Saat deploy ke production, set environment variable:

```bash
# Untuk 1 domain
export CORS_ALLOWED_ORIGINS=https://example.com

# Untuk multiple domains
export CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com,https://admin.example.com

# Dengan ports
export CORS_ALLOWED_ORIGINS=https://example.com:443,https://app.example.com:3000
```

Atau di Heroku:
```bash
heroku config:set CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com
```

---

## Troubleshooting

### "CORS error: Origin not allowed"

**Solusi:**
1. Check origin yang digunakan: Buka DevTools → Console → cari error message
2. Origin biasanya `http://localhost:5173` atau `http://localhost:3000`
3. Pastikan sudah ada di `CORS_ALLOWED_ORIGINS` di config atau `.env`

```bash
# Edit .env
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000
```

### "Missing CORS headers di response"

**Check:**
1. Apakah backend sudah running? (`http://localhost:4000` accessible?)
2. Apakah CORSPlug aktif di endpoint?
3. Apakah origin header ada di request?

### "Preflight request failing (404)"

**Solusi:**
1. CORSPlug harus handle OPTIONS request
2. Pastikan endpoint `/api/json/users` exist atau gunakan route lain
3. Test dengan route yang pasti ada

### "Cookie tidak dikirim ke backend"

**Pastikan frontend:**
```javascript
fetch('/api/json/users', {
  method: 'GET',
  credentials: 'include'  // ← Ini penting!
})
```

---

## Verifikasi CORS Configuration

Untuk verify config sudah benar, check file-file ini:

1. **`lib/ashapi_web/endpoint.ex`**
   - CORSPlug menggunakan `Application.compile_env(:ashapi, [:cors, :allowed_origins])`
   - Methods dan headers sudah di-whitelist

2. **`lib/ashapi_web/router.ex`**
   - CheckOrigin plug active di `:api` pipeline

3. **`.env` file**
   - `CORS_ALLOWED_ORIGINS` diset dengan origin(s) yang correct

4. **Development config: `config/dev.exs`**
   - `cors_allowed_origins` mencakup localhost:3000, 5173, 5174

---

## Production Checklist

Sebelum deploy ke production:

- [ ] Set `CORS_ALLOWED_ORIGINS` environment variable dengan domain yang benar
- [ ] Gunakan HTTPS (bukan HTTP)
- [ ] Jangan gunakan wildcard `*` dengan credentials
- [ ] Test CORS dengan curl sebelum go live
- [ ] Monitor CORS errors di production logs

---

## Helpful Links

- [MDN CORS Documentation](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [CORSPlug Documentation](https://github.com/mschae/cors_plug)
- [OWASP CORS](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Origin_Resource_Sharing_Cheat_Sheet.html)

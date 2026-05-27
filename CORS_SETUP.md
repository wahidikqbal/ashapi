# CORS Configuration Guide

## Overview

CORS (Cross-Origin Resource Sharing) is now properly configured in the Ashapi project. The configuration is environment-aware and secure.

## Configuration by Environment

### Development (`config/dev.exs`)

By default, development allows requests from:
- `http://localhost:3000` (common dev port)
- `http://localhost:5173` (Vite dev server - default)
- `http://localhost:5174` (Vite alternative)
- `http://127.0.0.1:3000`
- `http://127.0.0.1:5173`
- `http://127.0.0.1:5174`

**To modify:** Edit `config/dev.exs` and update the `cors_allowed_origins` list.

### Production (`config/runtime.exs`)

In production, CORS origins **must** be set via the `CORS_ALLOWED_ORIGINS` environment variable.

**Required Environment Variable:**

```bash
CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com
```

**Format:** Comma-separated list of allowed origins (no spaces recommended)

**Example values:**
```bash
# Single origin
CORS_ALLOWED_ORIGINS=https://example.com

# Multiple origins
CORS_ALLOWED_ORIGINS=https://example.com,https://app.example.com,https://admin.example.com

# With ports
CORS_ALLOWED_ORIGINS=https://example.com:443,https://app.example.com:3000
```

## Security Features

### 1. **Session Cookie Security**
- ✅ `HttpOnly: true` - JavaScript cannot access cookies (prevents XSS attacks)
- ✅ `Secure: true` (production only) - Cookies only sent over HTTPS
- ✅ `SameSite: Strict` - Strict CSRF protection

### 2. **CORSPlug Configuration**
```elixir
plug CORSPlug,
  origin: [...allowed origins...],
  credentials: true,  # Allow sending credentials (cookies/auth headers)
  methods: ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  headers: ["Content-Type", "Authorization", "Accept", "X-Requested-With"]
```

### 3. **Additional Origin Validation**
The `AshapiWeb.Plugs.CheckOrigin` plug provides an additional validation layer for API endpoints.

## Implementation Details

### Files Modified

1. **`lib/ashapi_web/endpoint.ex`**
   - Session cookies now use `same_site: "Strict"` and `http_only: true`
   - CORSPlug uses dynamic configuration from app env
   - Methods and headers allowlist added

2. **`config/config.exs`**
   - Base CORS configuration (overridden by env-specific configs)

3. **`config/dev.exs`**
   - Development-specific CORS origins

4. **`config/prod.exs`**
   - Production config (origins set at runtime)

5. **`config/runtime.exs`**
   - Reads `CORS_ALLOWED_ORIGINS` environment variable
   - Validates and parses comma-separated origins

6. **`lib/ashapi_web/middlewares/check_origin.ex`**
   - Updated to read from app env configuration
   - Provides additional origin validation

7. **`lib/ashapi_web/middlewares/token_form_cookie.ex`**
   - Enhanced with better guard clauses
   - Added validation for token format

8. **`lib/ashapi_web/router.ex`**
   - CheckOrigin plug now active in API pipeline

## Testing CORS

### Frontend/Client Configuration

When making requests from your frontend, ensure you're sending the correct headers:

```javascript
// Example: Fetch with credentials
fetch('http://localhost:4000/api/json/users', {
  method: 'GET',
  credentials: 'include', // Send cookies with request
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_TOKEN' // Or use cookie
  }
})
```

### Browser DevTools

1. Open Network tab in browser DevTools
2. Look for these response headers:
   ```
   Access-Control-Allow-Origin: http://localhost:5173
   Access-Control-Allow-Credentials: true
   Access-Control-Allow-Methods: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS
   ```

3. Preflight requests (OPTIONS) should return 200 OK

## Troubleshooting

### "CORS error: Origin not allowed"

**Solution:**
1. Check the origin in browser console (Network tab shows request origin)
2. Add the origin to `CORS_ALLOWED_ORIGINS` environment variable
3. Restart the application

### "Cookie not being sent"

**Check:**
1. Cookie domain must match request origin
2. Cookie must have `HttpOnly: true` set
3. Cookie must have `Secure: true` in production
4. Client must send `credentials: 'include'` in fetch/axios requests

### "Preflight request failing"

**Preflight requests (OPTIONS) are:**
- Automatically handled by CORSPlug
- Required before POST/PUT/PATCH/DELETE with custom headers
- Should return 200 OK with appropriate CORS headers

## Best Practices

1. ✅ **Always use HTTPS in production** - `Secure: true` requires it
2. ✅ **Be specific with origins** - Never use `["*"]` with credentials in production
3. ✅ **Use HttpOnly cookies** - Protects against XSS attacks
4. ✅ **Use SameSite Strict** - Protects against CSRF attacks
5. ✅ **Monitor CORS errors** - They indicate potential security issues
6. ✅ **Keep origins list minimal** - Only allow necessary origins

## Additional Security Considerations

- Token storage: Consider using HttpOnly cookies for JWTs
- Rate limiting: Implement per-origin rate limiting
- API versioning: Use versioned endpoints with different CORS policies if needed
- Monitoring: Log failed CORS validation attempts

# Ashapi Endpoints Reference

## Available API Endpoints

### Authentication & User Management
**Base:** `/api/json/users`
**Domain:** `Ashapi.Accounts`

#### User Authentication
```
POST /api/json/users/register
  - Register new user with password
  - Body: { user: { email: "...", password: "..." } }

POST /api/json/users/sign-in
  - Sign in with email & password
  - Body: { user: { email: "...", password: "..." } }
  
POST /api/json/users/request-password-reset-token
  - Request password reset
  
POST /api/json/users/reset-password-with-token
  - Reset password with token
  
POST /api/json/users/confirm-new-user
  - Confirm email address
```

#### User CRUD
```
GET /api/json/users
  - List all users
  - Authentication: Optional
  - Authorization: Public

GET /api/json/users/:id
  - Get specific user
  - Authentication: Optional

PUT /api/json/users/:id
  - Update user
  - Authentication: Required
  - Authorization: Own user only

DELETE /api/json/users/:id
  - Delete user
  - Authentication: Required
  - Authorization: Own user only
```

---

### Blog & Posts
**Base:** `/api/json/posts`
**Domain:** `Ashapi.Blog`

#### Post CRUD
```
GET /api/json/posts
  - List all posts
  - Authentication: Optional
  - Authorization: Public (read)

GET /api/json/posts/:id
  - Get specific post
  - Authentication: Optional

POST /api/json/posts
  - Create new post
  - Authentication: Required (must be logged in)
  - Body: { post: { title: "...", content: "..." } }

PUT /api/json/posts/:id
  - Update post
  - Authentication: Required
  - Authorization: Own post only

DELETE /api/json/posts/:id
  - Delete post
  - Authentication: Required
  - Authorization: Own post only
```

---

## Testing CORS for Each Endpoint

### 1. Test Users Endpoint

```bash
# Test with script
./test_cors.sh users

# Test with curl - Preflight
curl -v -X OPTIONS "http://localhost:4000/api/json/users" \
  -H "Origin: http://localhost:5173" \
  -H "Access-Control-Request-Method: GET"

# Test with curl - GET
curl -i "http://localhost:4000/api/json/users" \
  -H "Origin: http://localhost:5173"

# Test with curl - POST (create user)
curl -i -X POST "http://localhost:4000/api/json/users" \
  -H "Origin: http://localhost:5173" \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"test@example.com","password":"password123"}}'
```

### 2. Test Posts Endpoint

```bash
# Test with script
./test_cors.sh posts

# Test with curl - Preflight
curl -v -X OPTIONS "http://localhost:4000/api/json/posts" \
  -H "Origin: http://localhost:5173" \
  -H "Access-Control-Request-Method: GET"

# Test with curl - GET
curl -i "http://localhost:4000/api/json/posts" \
  -H "Origin: http://localhost:5173"

# Test with curl - POST (create post)
curl -i -X POST "http://localhost:4000/api/json/posts" \
  -H "Origin: http://localhost:5173" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"post":{"title":"My Post","content":"Post content here"}}'
```

---

## OpenAPI / Swagger Documentation

Access the interactive API documentation:

```
http://localhost:4000/api/json/swaggerui
```

---

## Browser Testing

### Using test_cors.html

Simply open `test_cors.html` in your browser and:
1. Set Backend URL: `http://localhost:4000`
2. Set Origin: `http://localhost:5173`
3. Click "Run Test" buttons

### Manual Browser Testing

Open browser Developer Tools (F12) and test with JavaScript:

```javascript
// Test Users endpoint
fetch('http://localhost:4000/api/json/users', {
  method: 'GET',
  headers: { 'Content-Type': 'application/json' },
  credentials: 'include'
})
.then(r => r.json())
.then(console.log)

// Test Posts endpoint
fetch('http://localhost:4000/api/json/posts', {
  method: 'GET',
  credentials: 'include'
})
.then(r => r.json())
.then(console.log)

// Create a new post (requires authentication)
fetch('http://localhost:4000/api/json/posts', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_TOKEN_HERE'
  },
  credentials: 'include',
  body: JSON.stringify({
    post: {
      title: 'My First Post',
      content: 'This is my first post!'
    }
  })
})
.then(r => r.json())
.then(console.log)
```

---

## Response Headers

### Successful Response (200 OK)

```
HTTP/1.1 200 OK
Content-Type: application/vnd.api+json
Access-Control-Allow-Origin: http://localhost:5173
Access-Control-Allow-Credentials: true
Content-Length: 123
```

### Preflight Response (204 No Content)

```
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: http://localhost:5173
Access-Control-Allow-Methods: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization, Accept, X-Requested-With
Access-Control-Allow-Credentials: true
Access-Control-Max-Age: 86400
```

### CORS Error Response

```
HTTP/1.1 403 Forbidden
Content-Type: text/plain

Forbidden - Origin not allowed
```

---

## Common Issues & Solutions

### 1. Missing CORS Headers

**Problem:** Response doesn't include `Access-Control-Allow-Origin` header

**Solution:**
- Check that origin is in `.env` CORS_ALLOWED_ORIGINS
- Verify CORS_ALLOWED_ORIGINS format: `http://localhost:5173,http://localhost:3000`
- Restart backend server

### 2. 403 Forbidden on API Request

**Problem:** Getting "Forbidden - Origin not allowed"

**Solution:**
- Check `CheckOrigin` plug is properly configured
- Verify origin in browser matches CORS config
- Check CORS_ALLOWED_ORIGINS environment variable

### 3. Cookie Not Being Sent

**Problem:** Authentication token cookie not included in requests

**Solution:**
- Verify cookie settings: `HttpOnly: true`, `SameSite: Strict`
- Client must use `credentials: 'include'` in fetch/axios
- Check cookie domain matches request origin

### 4. Preflight Request Failing

**Problem:** OPTIONS request returns error

**Solution:**
- CORSPlug should handle OPTIONS automatically
- Check backend is running and accessible
- Try direct curl test to verify backend response

---

## Performance & Security

### Caching Preflight Responses
The server sets `Access-Control-Max-Age: 86400` (24 hours) to cache preflight responses.

### Security Considerations
- ✅ Origins must be explicitly whitelisted
- ✅ Credentials only allowed with specific origins
- ✅ Cookies set with `HttpOnly`, `Secure`, `SameSite: Strict`
- ✅ Never use wildcard `*` with credentials in production

### Rate Limiting
Consider implementing rate limiting per-origin for production:
- Add middleware to limit requests per origin
- Log CORS violations for monitoring
- Alert on suspicious origin patterns

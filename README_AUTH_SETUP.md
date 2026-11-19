# Registration feature setup

## 1. Install the added dependencies

```powershell
npm install
```

## 2. Add JWT settings to your existing `.env`

Generate a local secret:

```powershell
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Copy the generated value into `.env`:

```env
JWT_SECRET=PASTE_YOUR_GENERATED_VALUE_HERE
JWT_EXPIRES_IN=1h
```

Do not share this secret or commit `.env` to Git.

## 3. Restart the API

```powershell
npm run dev
```

## 4. Test registration from a second PowerShell terminal

```powershell
$body = @{
  fullName = "Alex Morgan"
  email = "alex.morgan@example.com"
  password = "LocalDevPass123!"
  businessName = "Morgan General Stores"
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
  -Uri "http://localhost:4000/api/auth/register" `
  -ContentType "application/json" `
  -Body $body
```

Use an email address you have not registered before. The endpoint is:

`POST http://localhost:4000/api/auth/register`

The registration creates the business, user, owner membership and a PostgreSQL outbox event in one transaction. It returns a JWT access token. Passwords are stored as bcrypt hashes, never as plain text.

## Expected database checks

In pgAdmin, run:

```sql
SELECT id, name, slug, currency, timezone
FROM businesses
ORDER BY created_at DESC
LIMIT 5;

SELECT id, full_name, email, created_at
FROM users
ORDER BY created_at DESC
LIMIT 5;

SELECT business_id, user_id, role, status
FROM business_members
ORDER BY created_at DESC
LIMIT 5;

SELECT event_type, status, payload
FROM outbox_events
ORDER BY created_at DESC
LIMIT 5;
```

The password hash is deliberately not included in the user verification query.

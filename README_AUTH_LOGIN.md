# Authentication milestone: login and protected route

This update adds:

- `POST /api/auth/login` — verifies email/password and returns a JWT.
- `GET /api/auth/me` — protected route requiring `Authorization: Bearer <token>`.
- `authenticate` middleware — verifies the JWT and rechecks the user's active membership and business status in PostgreSQL on every protected request.

No new dependencies or SQL migrations are required for this update.

## Apply the update

1. Stop the API with `Ctrl+C`.
2. Extract this ZIP and merge the included `inventory-management-system` directory into your existing project directory, replacing files when prompted.
3. Keep your existing `.env` file. Do not replace it with `.env.example`.
4. Run `npm install` (there are no new dependencies, but this confirms the package lock and install are current).
5. Run `npm run dev`.

## Test login in PowerShell

Use the email/password of the owner already registered. Store the response in a variable so the token is not printed to the terminal:

```powershell
$loginBody = @{
    email = "alex.morgan@example.com"
    password = "YOUR_REGISTERED_PASSWORD"
} | ConvertTo-Json

$login = Invoke-RestMethod `
    -Method Post `
    -Uri "http://localhost:4000/api/auth/login" `
    -ContentType "application/json" `
    -Body $loginBody

$login.data.user | Format-List
$login.data.business | Format-List
```

## Test the protected route without a token

```powershell
try {
    Invoke-RestMethod -Uri "http://localhost:4000/api/auth/me"
} catch {
    $_.ErrorDetails.Message
}
```

Expected: HTTP 401 and a message that authentication is required.

## Test the protected route with the token

```powershell
$headers = @{
    Authorization = "Bearer $($login.data.accessToken)"
}

Invoke-RestMethod `
    -Uri "http://localhost:4000/api/auth/me" `
    -Headers $headers | ConvertTo-Json -Depth 6
```

Expected: HTTP 200 with the authenticated user's details, active business details and role.

Do not paste or share the access token. Keep it in the local PowerShell variable.

## Selecting a business

For now, login without `businessId` selects the user's first active business membership. A client can pass an optional `businessId` to select a particular active business. The response also includes `availableBusinesses`. We'll add a dedicated business-switching flow when we build the workspace interface.

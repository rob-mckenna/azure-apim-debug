# APIM API Debug Scripts

This repository contains helper scripts to debug Azure API Management (APIM) APIs using request tracing.

The scripts automate the official APIM trace workflow:

1. Get a short-lived debug token from APIM management API.
2. Call the target API with the `Apim-Debug-Authorization` header.
3. Read `Apim-Trace-Id` from the API response headers.
4. Fetch full trace details from APIM and save them to `apim-trace.json`.

## Source

These scripts are based on Microsoft Learn guidance:

- https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-api-inspector

## Files

- `scripts/apim-debug.sh`: Bash script for Git Bash, WSL, or Linux/macOS shells.
- `scripts/apim-debug.ps1`: PowerShell script for Windows/PowerShell users.
- `scripts/apim-debug.http`: VS Code REST Client sequence to run the same flow interactively.

## Prerequisites

- Azure API Management instance and a published API.
- APIM subscription key for invoking the target API.
- Azure RBAC on the APIM resource: Contributor or higher (needed for management trace APIs).
- Azure CLI (`az`) authenticated to the correct tenant/subscription.
- For Bash script: `jq` installed.
- For `.http` file: VS Code REST Client extension.

## Important Notes

- Do not use deprecated `Ocp-Apim-Trace` header. These scripts use the modern debug token flow.
- Debug token expiry is set to `PT1H` (max 1 hour).
- Traces may contain sensitive data. Treat `apim-trace.json` as sensitive and do not commit it.
- `apiId` must be the APIM API identifier, not the display name from the portal.

## How to find API ID

Use Azure CLI:

```bash
az apim api list --resource-group <resource-group> --service-name <apim-name> -o table
```

Use the API name/identifier value from the output for `API_ID` / `ApiId`.

## Usage

### 1) Bash script

Set required environment variables and run:

```bash
cd c:/Repos/az-apim-debug
chmod +x scripts/apim-debug.sh

export SUBSCRIPTION_ID="<subscription-id>"
export RESOURCE_GROUP="<resource-group>"
export APIM_NAME="<apim-name>"
export API_ID="<api-id>"
export GATEWAY_URL="https://<apim-name>.azure-api.net"
export SUBSCRIPTION_KEY="<subscription-key>"

# Optional
export API_PATH="/pet/1"
export REQUEST_METHOD="GET"
# export REQUEST_BODY='{"sample":"value"}'

./scripts/apim-debug.sh
```

Output:

- `apim-trace.json` in current working directory.
- Response body printed to terminal.

### 2) PowerShell script

Run with required parameters:

```powershell
cd c:\Repos\az-apim-debug

.\scripts\apim-debug.ps1 `
  -SubscriptionId "<subscription-id>" `
  -ResourceGroup "<resource-group>" `
  -ApimName "<apim-name>" `
  -ApiId "<api-id>" `
  -GatewayUrl "https://<apim-name>.azure-api.net" `
  -ApiPath "/pet/1" `
  -SubscriptionKey "<subscription-key>" `
  -Method GET
```

Optional for body-based methods:

```powershell
-Method POST -RequestBody '{"sample":"value"}'
```

Output:

- `apim-trace.json` in current working directory.
- Status code displayed in terminal.

### 3) VS Code REST Client file

1. Open `scripts/apim-debug.http`.
2. Replace all placeholder values at the top.
3. Execute requests in order:
   - `login`
   - `listDebugCredentials`
   - `callApi`
   - `getTrace`
4. Review trace payload in REST Client response.

## Common Troubleshooting

- Missing `Apim-Trace-Id` header:
  - Check if response includes `Apim-Debug-Authorization-Expired`.
  - Check if response includes `Apim-Debug-Authorization-WrongAPI`.
  - Verify `ApiId` matches the API you are calling.
- 401/403 from management endpoints:
  - Verify Azure CLI login context and RBAC role on APIM.
- API call fails before trace retrieval:
  - Confirm gateway URL, path, and subscription key are correct.

## Security Hygiene

- Add `apim-trace.json` to `.gitignore` if you plan to run frequently.
- Avoid sharing trace files in tickets/chats without redacting secrets.

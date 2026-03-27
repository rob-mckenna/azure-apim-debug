# APIM API Debug Scripts

This repository contains helper scripts to debug Azure API Management (APIM) APIs using request tracing.

The scripts automate the official APIM trace workflow:

1. Get a short-lived debug token from APIM management API.
2. Call the target API with the `Apim-Debug-Authorization` header.
3. Read `Apim-Trace-Id` from the API response headers.
4. Fetch full trace details from APIM and save them to `apim-trace.json`.

## Source

These scripts are based on Microsoft Learn guidance:

- [APIM API Inspector guidance](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-api-inspector)

## Files

- `scripts/apim-debug.sh`: Bash script for Git Bash, WSL, or Linux/macOS shells.
- `scripts/apim-debug.ps1`: PowerShell script for Windows/PowerShell users.
- `scripts/apim-debug.http`: VS Code REST Client sequence to run the same flow interactively.
- `scripts/apim-debug.env.example`: Template for shared environment values.

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

## Environment Values Reference

These values are defined in `scripts/apim-debug.env` (copied from `scripts/apim-debug.env.example`).

| Value | Required | Description | Example |
| --- | --- | --- | --- |
| `SUBSCRIPTION_ID` | Yes | Azure subscription GUID that contains the APIM instance. | `11111111-2222-3333-4444-555555555555` |
| `RESOURCE_GROUP` | Yes | Resource group name where the APIM service is deployed. | `rg-api-prod` |
| `APIM_NAME` | Yes | APIM service name (not display name). | `contoso-apim-prod` |
| `API_ID` | Yes | APIM API identifier under the APIM service. This must match the API being called. | `petstore-v1` |
| `GATEWAY_URL` | Yes | Full APIM **gateway/proxy** base URL including protocol, without trailing API path. Use `*.azure-api.net` (or your custom proxy host), not `*.developer.azure-api.net`. | `https://contoso-apim-prod.azure-api.net` |
| `SUBSCRIPTION_KEY` | Yes | APIM subscription key used to invoke the API operation. Treat as a secret. | `<primary-or-secondary-key>` |
| `API_PATH` | No | Operation path appended to `GATEWAY_URL`. Defaults to `/pet/1` when omitted. | `/pet/1` |
| `REQUEST_METHOD` | No | HTTP method for the gateway call. Supported values: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`. Defaults to `GET`. | `POST` |
| `REQUEST_BODY` | No | Request payload sent when body is needed. Leave empty for bodyless requests. | `{"id":1,"name":"fido"}` |

Notes:

- Bash script behavior: values are read from `scripts/apim-debug.env` by default, and you can change the file path with `ENV_FILE`.
- PowerShell script behavior: values are read from `scripts/apim-debug.env` by default, and you can change the file path with `-EnvFile`.
- Command-line and inline overrides still work for single runs and take precedence over file defaults.

## Usage

### 1) Bash script

Create a local environment file once, then run:

```bash
cd c:/Repos/azure-apim-debug
cp scripts/apim-debug.env.example scripts/apim-debug.env
# Edit scripts/apim-debug.env with your values.

chmod +x scripts/apim-debug.sh

./scripts/apim-debug.sh
```

Optional overrides:

```bash
# Override values for one run
API_PATH="/pet/2" REQUEST_METHOD="GET" ./scripts/apim-debug.sh

# Use a different env file
ENV_FILE="./scripts/apim-debug.dev.env" ./scripts/apim-debug.sh
```

Output:

- `apim-trace.json` in current working directory.
- Response body printed to terminal.

### 2) PowerShell script

Create a local environment file once, then run:

```powershell
cd c:\Repos\azure-apim-debug
Copy-Item .\scripts\apim-debug.env.example .\scripts\apim-debug.env
# Edit .\scripts\apim-debug.env with your values.

.\scripts\apim-debug.ps1
```

Optional overrides:

```powershell
.\scripts\apim-debug.ps1 -Method POST -RequestBody '{"sample":"value"}'

# Use a different env file
.\scripts\apim-debug.ps1 -EnvFile .\scripts\apim-debug.dev.env
```

Any parameter can still be passed directly to override the env file for a single run.

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

- Keep `scripts/apim-debug.env` local only. It contains secrets and should not be committed.
- `apim-trace.json` can contain sensitive data; keep it out of source control.
- Avoid sharing trace files in tickets/chats without redacting secrets.

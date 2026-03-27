param(
  [string] $EnvFile = (Join-Path $PSScriptRoot "apim-debug.env"),
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $ApimName,
  [string] $ApiId,
  [string] $GatewayUrl,
  [string] $ApiPath,
  [string] $SubscriptionKey,
  [ValidateSet("GET","POST","PUT","DELETE","PATCH")] [string] $Method = "GET",
  [string] $RequestBody = ""
)

$ErrorActionPreference = "Stop"

function Get-DotEnvValues {
  param([string] $Path)

  $result = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $result
  }

  foreach ($rawLine in Get-Content -LiteralPath $Path) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      continue
    }

    if ($line -match '^[\s]*([A-Za-z_][A-Za-z0-9_]*)[\s]*=[\s]*(.*)$') {
      $key = $matches[1]
      $value = $matches[2].Trim()

      if (
        ($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))
      ) {
        $value = $value.Substring(1, $value.Length - 2)
      }

      $result[$key] = $value
    }
  }

  return $result
}

$envValues = Get-DotEnvValues -Path $EnvFile

if (-not $SubscriptionId) { $SubscriptionId = $envValues["SUBSCRIPTION_ID"] }
if (-not $ResourceGroup) { $ResourceGroup = $envValues["RESOURCE_GROUP"] }
if (-not $ApimName) { $ApimName = $envValues["APIM_NAME"] }
if (-not $ApiId) { $ApiId = $envValues["API_ID"] }
if (-not $GatewayUrl) { $GatewayUrl = $envValues["GATEWAY_URL"] }
if (-not $SubscriptionKey) { $SubscriptionKey = $envValues["SUBSCRIPTION_KEY"] }
if (-not $ApiPath) { $ApiPath = $envValues["API_PATH"] }
if (-not $RequestBody) { $RequestBody = $envValues["REQUEST_BODY"] }

if ($PSBoundParameters.ContainsKey("Method") -eq $false -and $envValues.ContainsKey("REQUEST_METHOD")) {
  $Method = $envValues["REQUEST_METHOD"].ToUpperInvariant()
}

if ([string]::IsNullOrWhiteSpace($ApiPath)) {
  $ApiPath = "/pet/1"
}

$validMethods = @("GET", "POST", "PUT", "DELETE", "PATCH")
if ($validMethods -notcontains $Method) {
  throw "Invalid method '$Method'. Valid values: $($validMethods -join ', ')"
}

$requiredValues = @{
  SUBSCRIPTION_ID = $SubscriptionId
  RESOURCE_GROUP = $ResourceGroup
  APIM_NAME = $ApimName
  API_ID = $ApiId
  GATEWAY_URL = $GatewayUrl
  SUBSCRIPTION_KEY = $SubscriptionKey
}

$missing = @($requiredValues.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) } | ForEach-Object { $_.Key })
if ($missing.Count -gt 0) {
  throw "Missing required values: $($missing -join ', '). Provide via parameters or env file at '$EnvFile'."
}

if ($GatewayUrl -like "*your-apim-name.azure-api.net*" -or $GatewayUrl -like "*<your-apim-gateway-hostname>*") {
  throw "GATEWAY_URL appears to be a placeholder. Update it in '$EnvFile' (for example: https://$ApimName.azure-api.net)."
}

if ($GatewayUrl -notmatch '^https?://') {
  throw "GATEWAY_URL must start with http:// or https://"
}

Write-Host "Getting ARM token..."
$mgmtToken = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
if (-not $mgmtToken) {
  throw "Could not get ARM token from Azure CLI."
}

$apiResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/$ApiId"
$debugUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/gateways/managed/listDebugCredentials?api-version=2023-05-01-preview"

$debugBody = @{
  credentialsExpireAfter = "PT1H"
  apiId = $apiResourceId
  purposes = @("tracing")
} | ConvertTo-Json -Depth 10

Write-Host "Requesting APIM debug token..."
$debugResp = Invoke-RestMethod -Method Post -Uri $debugUrl -Headers @{
  Authorization = "Bearer $mgmtToken"
  "Content-Type" = "application/json"
} -Body $debugBody

$debugToken = $debugResp.token
if (-not $debugToken) {
  throw "Failed to get debug token. Verify ApiId and APIM RBAC permissions."
}

$headers = @{
  "Ocp-Apim-Subscription-Key" = $SubscriptionKey
  "Apim-Debug-Authorization"  = $debugToken
}

$uri = "$GatewayUrl$ApiPath"
Write-Host "Calling API with trace enabled: $uri"

if ([string]::IsNullOrWhiteSpace($RequestBody)) {
  $apiResp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers
} else {
  $apiResp = Invoke-WebRequest -Method $Method -Uri $uri -Headers ($headers + @{ "Content-Type" = "application/json" }) -Body $RequestBody
}

$traceId = $apiResp.Headers["Apim-Trace-Id"]
if (-not $traceId) {
  $expired = $apiResp.Headers["Apim-Debug-Authorization-Expired"]
  $wrongApi = $apiResp.Headers["Apim-Debug-Authorization-WrongAPI"]
  throw "Trace ID missing. Expired=$expired WrongAPI=$wrongApi"
}

Write-Host "Trace ID: $traceId"

$traceUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/gateways/managed/listTrace?api-version=2024-06-01-preview"
$traceBody = @{ traceId = $traceId } | ConvertTo-Json

Write-Host "Downloading trace..."
$traceResp = Invoke-RestMethod -Method Post -Uri $traceUrl -Headers @{
  Authorization = "Bearer $mgmtToken"
  "Content-Type" = "application/json"
} -Body $traceBody

$traceResp | ConvertTo-Json -Depth 100 | Out-File -FilePath ".\apim-trace.json" -Encoding utf8
Write-Host "Saved trace to .\apim-trace.json"
Write-Host "API response status code: $($apiResp.StatusCode)"

param(
  [Parameter(Mandatory=$true)] [string] $SubscriptionId,
  [Parameter(Mandatory=$true)] [string] $ResourceGroup,
  [Parameter(Mandatory=$true)] [string] $ApimName,
  [Parameter(Mandatory=$true)] [string] $ApiId,
  [Parameter(Mandatory=$true)] [string] $GatewayUrl,
  [Parameter(Mandatory=$true)] [string] $ApiPath,
  [Parameter(Mandatory=$true)] [string] $SubscriptionKey,
  [ValidateSet("GET","POST","PUT","DELETE","PATCH")] [string] $Method = "GET",
  [string] $RequestBody = ""
)

$ErrorActionPreference = "Stop"

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

#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
# SUBSCRIPTION_ID RESOURCE_GROUP APIM_NAME API_ID GATEWAY_URL SUBSCRIPTION_KEY
# Optional env vars:
# API_PATH (default /pet/1)
# REQUEST_METHOD (default GET)
# REQUEST_BODY (default empty)

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
APIM_NAME="${APIM_NAME:-}"
API_ID="${API_ID:-}"
GATEWAY_URL="${GATEWAY_URL:-}"
SUBSCRIPTION_KEY="${SUBSCRIPTION_KEY:-}"
API_PATH="${API_PATH:-/pet/1}"
REQUEST_METHOD="${REQUEST_METHOD:-GET}"
REQUEST_BODY="${REQUEST_BODY:-}"

if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" || -z "$APIM_NAME" || -z "$API_ID" || -z "$GATEWAY_URL" || -z "$SUBSCRIPTION_KEY" ]]; then
  echo "Missing required env vars."
  echo "Set: SUBSCRIPTION_ID RESOURCE_GROUP APIM_NAME API_ID GATEWAY_URL SUBSCRIPTION_KEY"
  exit 1
fi

command -v az >/dev/null || { echo "Azure CLI (az) is required."; exit 1; }
command -v jq >/dev/null || { echo "jq is required."; exit 1; }

echo "Getting ARM token..."
MGMT_TOKEN="$(az account get-access-token --resource https://management.azure.com --query accessToken -o tsv)"

API_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/apis/${API_ID}"
DEBUG_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/gateways/managed/listDebugCredentials?api-version=2023-05-01-preview"

DEBUG_PAYLOAD="$(cat <<JSON
{
  "credentialsExpireAfter": "PT1H",
  "apiId": "${API_RESOURCE_ID}",
  "purposes": ["tracing"]
}
JSON
)"

echo "Requesting APIM debug token..."
DEBUG_TOKEN="$(curl -sS -X POST "$DEBUG_URL" \
  -H "Authorization: Bearer ${MGMT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$DEBUG_PAYLOAD" | jq -r '.token')"

if [[ -z "$DEBUG_TOKEN" || "$DEBUG_TOKEN" == "null" ]]; then
  echo "Failed to get debug token. Check API_ID and RBAC on APIM."
  exit 1
fi

RESP_HEADERS="$(mktemp)"
RESP_BODY="$(mktemp)"

echo "Calling API with Apim-Debug-Authorization..."
if [[ -n "$REQUEST_BODY" ]]; then
  curl -sS -X "$REQUEST_METHOD" "${GATEWAY_URL}${API_PATH}" \
    -H "Ocp-Apim-Subscription-Key: ${SUBSCRIPTION_KEY}" \
    -H "Apim-Debug-Authorization: ${DEBUG_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" \
    -D "$RESP_HEADERS" -o "$RESP_BODY"
else
  curl -sS -X "$REQUEST_METHOD" "${GATEWAY_URL}${API_PATH}" \
    -H "Ocp-Apim-Subscription-Key: ${SUBSCRIPTION_KEY}" \
    -H "Apim-Debug-Authorization: ${DEBUG_TOKEN}" \
    -D "$RESP_HEADERS" -o "$RESP_BODY"
fi

TRACE_ID="$(grep -i '^Apim-Trace-Id:' "$RESP_HEADERS" | awk '{print $2}' | tr -d '\r')"

if [[ -z "$TRACE_ID" ]]; then
  echo "Trace ID not found. Check these headers from the gateway response:"
  grep -i '^Apim-Debug-Authorization-Expired:' "$RESP_HEADERS" || true
  grep -i '^Apim-Debug-Authorization-WrongAPI:' "$RESP_HEADERS" || true
  echo "Full response headers:"
  cat "$RESP_HEADERS"
  exit 1
fi

echo "Trace ID: $TRACE_ID"

TRACE_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/gateways/managed/listTrace?api-version=2024-06-01-preview"

echo "Downloading trace..."
curl -sS -X POST "$TRACE_URL" \
  -H "Authorization: Bearer ${MGMT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{ \"traceId\": \"${TRACE_ID}\" }" | jq . > apim-trace.json

echo "Saved trace to apim-trace.json"
echo "Response body:"
cat "$RESP_BODY"

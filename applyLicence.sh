#!/usr/bin/env bash

LICENCE=$(echo "$1" | base64 -d)
LOCAL_PORT=${2:-5705}
USERNAME=${3:-'storageos'}
PASSWORD=${4:-'storageos'}
REMOTE_PORT=5705

# forwards remote api port to localhost
echo "Creating port forward to ondat's cluster api"
kubectl port-forward \
  -n storageos svc/storageos \
  "$LOCAL_PORT":"$REMOTE_PORT" >/dev/null 2>&1 &

PORT_FORWARD_PID=$!

# kills the port-forward regardless of how this script exits
trap '{
    echo Killing port forward process $PORT_FORWARD_PID
    kill $PORT_FORWARD_PID
}' EXIT

# waits for the local port to become available
while ! nc -vz localhost "$LOCAL_PORT" >/dev/null 2>&1; do
  sleep 0.1
done

# retrieves the auth token from ondat's cluster api
echo "Authenticating against ondat's cluster api"
AUTH_TOKEN=$(
  curl \
    --silent \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}" \
    http://localhost:"$LOCAL_PORT"/v2/auth/login 2>&1 |
    jq -r .session.token
)

echo "Retrieving entity version for licence"
LICENCE_VERSION=$(
  curl \
    --silent \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    http://localhost:"$LOCAL_PORT"/v2/cluster/licence 2>&1 |
    jq -r .version
)

LICENSE_PAYLOAD=$(
  jq -n -r \
    --arg key "$LICENCE" \
    --arg version "$LICENCE_VERSION" \
    '{ key: $key, version: $version }'
)

# pass licence to ondat's cluster api
echo "Applying new licence"
curl \
  -X PUT \
  --silent \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "$LICENSE_PAYLOAD" \
  http://localhost:"$LOCAL_PORT"/v2/cluster/licence | jq .

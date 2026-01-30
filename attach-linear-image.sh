#!/bin/bash

# Attach an image to a Linear ticket
# Usage: ./attach-linear-image.sh <issue-id> <image-path>
#
# Example: ./attach-linear-image.sh ENG-333 /path/to/screenshot.png
#
# Requires: LINEAR_API_TOKEN environment variable

set -e

ISSUE_ID="$1"
IMAGE_PATH="$2"

if [ -z "$ISSUE_ID" ] || [ -z "$IMAGE_PATH" ]; then
  echo "Usage: $0 <issue-id> <image-path>"
  echo "Example: $0 ENG-333 /path/to/screenshot.png"
  exit 1
fi

if [ -z "$LINEAR_API_TOKEN" ]; then
  echo "Error: LINEAR_API_TOKEN environment variable is not set"
  exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
  echo "Error: File not found: $IMAGE_PATH"
  exit 1
fi

# Get filename and detect content type
FILENAME=$(basename "$IMAGE_PATH")
EXTENSION="${FILENAME##*.}"

case "$EXTENSION" in
  png)  CONTENT_TYPE="image/png" ;;
  jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
  gif)  CONTENT_TYPE="image/gif" ;;
  webp) CONTENT_TYPE="image/webp" ;;
  *)    CONTENT_TYPE="application/octet-stream" ;;
esac

FILESIZE=$(stat -f%z "$IMAGE_PATH" 2>/dev/null || stat -c%s "$IMAGE_PATH" 2>/dev/null)

# Step 1: Get the issue UUID from the identifier
ISSUE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_TOKEN" \
  --data "$(jq -n --arg id "$ISSUE_ID" '{
    query: "query GetIssue($id: String!) { issue(id: $id) { id identifier } }",
    variables: { id: $id }
  }')" \
  https://api.linear.app/graphql)

ISSUE_UUID=$(echo "$ISSUE_RESPONSE" | jq -r '.data.issue.id')

if [ -z "$ISSUE_UUID" ] || [ "$ISSUE_UUID" == "null" ]; then
  echo "Error: Could not find issue $ISSUE_ID"
  echo "Response: $ISSUE_RESPONSE"
  exit 1
fi

# Step 2: Request an upload URL from Linear
UPLOAD_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_TOKEN" \
  --data "$(jq -n \
    --arg filename "$FILENAME" \
    --arg contentType "$CONTENT_TYPE" \
    --argjson size "$FILESIZE" \
    '{
      query: "mutation FileUpload($filename: String!, $contentType: String!, $size: Int!) { fileUpload(filename: $filename, contentType: $contentType, size: $size) { success uploadFile { filename contentType size uploadUrl assetUrl headers { key value } } } }",
      variables: { filename: $filename, contentType: $contentType, size: $size }
    }')" \
  https://api.linear.app/graphql)

UPLOAD_SUCCESS=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.fileUpload.success')

if [ "$UPLOAD_SUCCESS" != "true" ]; then
  echo "Error: Failed to get upload URL"
  echo "Response: $UPLOAD_RESPONSE"
  exit 1
fi

UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.fileUpload.uploadFile.uploadUrl')
ASSET_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.fileUpload.uploadFile.assetUrl')

# Build headers array for the upload
HEADERS=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.fileUpload.uploadFile.headers[] | "-H \"" + .key + ": " + .value + "\""' | tr '\n' ' ')

# Step 3: Upload the file
eval "curl -s -X PUT \
  -H 'Content-Type: $CONTENT_TYPE' \
  $HEADERS \
  --data-binary '@$IMAGE_PATH' \
  '$UPLOAD_URL'" > /dev/null

# Step 4: Get current description and prepend the image
DESC_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_TOKEN" \
  --data "$(jq -n --arg id "$ISSUE_UUID" '{
    query: "query GetDesc($id: String!) { issue(id: $id) { description } }",
    variables: { id: $id }
  }')" \
  https://api.linear.app/graphql)

CURRENT_DESC=$(echo "$DESC_RESPONSE" | jq -r '.data.issue.description // ""')

# Insert image after first line (the summary)
FIRST_LINE=$(echo "$CURRENT_DESC" | head -1)
REST=$(echo "$CURRENT_DESC" | tail -n +2)
NEW_DESC="${FIRST_LINE}

![${FILENAME}](${ASSET_URL})
${REST}"

# Step 5: Update the issue description with the image
UPDATE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_TOKEN" \
  --data "$(jq -n \
    --arg id "$ISSUE_UUID" \
    --arg desc "$NEW_DESC" \
    '{
      query: "mutation UpdateIssue($id: String!, $description: String!) { issueUpdate(id: $id, input: { description: $description }) { success } }",
      variables: { id: $id, description: $desc }
    }')" \
  https://api.linear.app/graphql)

UPDATE_SUCCESS=$(echo "$UPDATE_RESPONSE" | jq -r '.data.issueUpdate.success')

if [ "$UPDATE_SUCCESS" == "true" ]; then
  echo "✓ Attached $FILENAME to $ISSUE_ID"
  echo "Asset URL: $ASSET_URL"
else
  echo "Error: Failed to update issue description"
  echo "Response: $UPDATE_RESPONSE"
  exit 1
fi

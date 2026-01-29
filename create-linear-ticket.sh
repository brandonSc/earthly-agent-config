#!/bin/bash

# Linear ticket creation script for earthly-technologies/ENG team
# Usage: ./create-linear-ticket.sh "Title" "Description"

set -e

TITLE="$1"
DESCRIPTION="$2"

if [ -z "$TITLE" ]; then
  echo "Usage: $0 \"Title\" \"Description\""
  exit 1
fi

API_TOKEN="${LINEAR_API_TOKEN:-lin_api_vvYm3akuIpe5h491xWZ49cUHl3UzzU1srnO6cAJP}"

# First, get the team ID for ENG
TEAM_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $API_TOKEN" \
  --data '{"query": "{ teams { nodes { id key name } } }"}' \
  https://api.linear.app/graphql)

TEAM_ID=$(echo "$TEAM_RESPONSE" | jq -r '.data.teams.nodes[] | select(.key == "ENG") | .id')

if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" == "null" ]; then
  echo "Error: Could not find ENG team"
  echo "Response: $TEAM_RESPONSE"
  exit 1
fi

# Create the issue (escape quotes and newlines for JSON)
ESCAPED_TITLE=$(printf '%s' "$TITLE" | sed 's/"/\\"/g')
ESCAPED_DESC=$(printf '%s' "$DESCRIPTION" | sed 's/"/\\"/g' | tr '\n' ' ')

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $API_TOKEN" \
  --data "{\"query\": \"mutation { issueCreate(input: { teamId: \\\"$TEAM_ID\\\", title: \\\"$ESCAPED_TITLE\\\", description: \\\"$ESCAPED_DESC\\\" }) { success issue { id identifier url title } } }\"}" \
  https://api.linear.app/graphql)

SUCCESS=$(echo "$RESPONSE" | jq -r '.data.issueCreate.success')

if [ "$SUCCESS" == "true" ]; then
  URL=$(echo "$RESPONSE" | jq -r '.data.issueCreate.issue.url')
  IDENTIFIER=$(echo "$RESPONSE" | jq -r '.data.issueCreate.issue.identifier')
  echo "✓ Created ticket $IDENTIFIER"
  echo "$URL"
else
  echo "Error creating ticket:"
  echo "$RESPONSE" | jq .
  exit 1
fi

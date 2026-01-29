#!/bin/bash

# Linear ticket creation script for earthly-technologies/ENG team
# Usage: ./create-linear-ticket.sh "Title" "Description"
#
# Requires: LINEAR_API_TOKEN environment variable
# The description supports full markdown formatting.

set -e

TITLE="$1"
DESCRIPTION="$2"

# Append AI attribution note
AI_NOTE="---
*This ticket was drafted by AI.*"
DESCRIPTION="${DESCRIPTION}

${AI_NOTE}"

if [ -z "$TITLE" ]; then
  echo "Usage: $0 \"Title\" \"Description\""
  echo ""
  echo "Environment: LINEAR_API_TOKEN must be set"
  exit 1
fi

if [ -z "$LINEAR_API_TOKEN" ]; then
  echo "Error: LINEAR_API_TOKEN environment variable is not set"
  exit 1
fi

# Get the team ID for ENG
TEAM_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_TOKEN" \
  --data '{"query": "{ teams { nodes { id key name } } }"}' \
  https://api.linear.app/graphql)

TEAM_ID=$(echo "$TEAM_RESPONSE" | jq -r '.data.teams.nodes[] | select(.key == "ENG") | .id')

if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" == "null" ]; then
  echo "Error: Could not find ENG team"
  echo "Response: $TEAM_RESPONSE"
  exit 1
fi

# Create the issue using GraphQL variables (handles escaping properly)
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_TOKEN" \
  --data "$(jq -n \
    --arg teamId "$TEAM_ID" \
    --arg title "$TITLE" \
    --arg desc "$DESCRIPTION" \
    '{
      query: "mutation CreateIssue($teamId: String!, $title: String!, $description: String) { issueCreate(input: { teamId: $teamId, title: $title, description: $description }) { success issue { id identifier url title } } }",
      variables: { teamId: $teamId, title: $title, description: $desc }
    }')" \
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

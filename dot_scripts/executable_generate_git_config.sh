#!/bin/bash

# Default to using credential process
USE_CREDENTIAL_PROCESS=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --inline-credentials)
      USE_CREDENTIAL_PROCESS=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

TAG="TYPE:GIT_SSH_KEY"
OUTPUT_FILE="$HOME/.aws/config"
CREDENTIALS_FILE="$HOME/.aws/credentials"

# Check for required tools
command -v op >/dev/null 2>&1 || { echo "Error: 1Password CLI (op) is required."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required."; exit 1; }

# Ensure 1Password CLI is signed in
op whoami >/dev/null 2>&1 || eval $(op signin)

# Create or clear output file
mkdir -p "$(dirname "$OUTPUT_FILE")"
> "$OUTPUT_FILE"
> "$CREDENTIALS_FILE"

# Get items with the specified tag
items=$(op item list --tags "$TAG" --format json)

# Check if items exist
if [ -z "$items" ] || [ "$items" = "[]" ]; then
  echo "# No AWS profiles found" > "$OUTPUT_FILE"
  exit 0
fi

# Process each item and append to config
echo "$items" | jq -c '.[]' | while read -r item; do
  title=$(echo "$item" | jq -r '.title')
  vault_name=$(echo "$item" | jq -r '.vault.name')
  profile_name=$(echo "$item" | jq -r --arg tag "$TAG" '.tags[] | select(startswith($tag + "/")) | sub($tag + "/"; "")')
  region=$(echo "$item" | jq -r '.tags[] | select(startswith("REGION:")) | sub("REGION:"; "")')

  if [ -z "$profile_name" ]; then
    echo "Skipping item '$title': No profile name found in tags beginning with '$TAG'."
    continue
  fi

  if [ "$USE_CREDENTIAL_PROCESS" = true ]; then
    # Write profile section using credential process
    cat <<EOF >> "$OUTPUT_FILE"
[profile $profile_name]
credential_process = sh -c "op item get '$title' --vault '$vault_name' --format json --reveal --fields label='AccessKeyId',label='SecretAccessKey' | jq 'map({key: .label, value: .value}) | from_entries + {Version: 1}'"
EOF
  else
    # Get credentials directly from 1Password
    credentials=$(op item get "$title" --vault "$vault_name" --format json --reveal --fields label='AccessKeyId',label='SecretAccessKey')
    access_key=$(echo "$credentials" | jq -r '.[] | select(.label=="AccessKeyId") | .value')
    secret_key=$(echo "$credentials" | jq -r '.[] | select(.label=="SecretAccessKey") | .value')

    # Write to credentials file
    cat <<EOF >> "$CREDENTIALS_FILE"
[$profile_name]
aws_access_key_id = $access_key
aws_secret_access_key = $secret_key

EOF

    # Write to config file
    cat <<EOF >> "$OUTPUT_FILE"
[profile $profile_name]
EOF
  fi

  if [ -n "$region" ] && [ "$region" != "null" ]; then
    echo "region = $region" >> "$OUTPUT_FILE"
  fi

  echo "" >> "$OUTPUT_FILE"
done

echo "AWS config generated at $OUTPUT_FILE"
if [ "$USE_CREDENTIAL_PROCESS" = false ]; then
  echo "AWS credentials generated at $CREDENTIALS_FILE"
fi
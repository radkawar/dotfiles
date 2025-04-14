#!/bin/bash

TAG="TYPE:AWS_ACCESS_KEY"
OUTPUT_FILE="$HOME/.aws/config"

# Check for required tools
command -v op >/dev/null 2>&1 || { echo "Error: 1Password CLI (op) is required."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required."; exit 1; }

# Ensure 1Password CLI is signed in
op whoami >/dev/null 2>&1 || eval $(op signin)

# Create or clear output file
mkdir -p "$(dirname "$OUTPUT_FILE")"
> "$OUTPUT_FILE"

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

  # Write profile section
  cat <<EOF >> "$OUTPUT_FILE"
[profile $profile_name]
credential_process = sh -c "op item get '$title' --vault '$vault_name' --format json --reveal --fields label='AccessKeyId',label='SecretAccessKey' | jq 'map({key: .label, value: .value}) | from_entries + {Version: 1}'"
EOF

  if [ -n "$region" ] && [ "$region" != "null" ]; then
    echo "region = $region" >> "$OUTPUT_FILE"
  fi

  echo "" >> "$OUTPUT_FILE"
done

echo "AWS config generated at $OUTPUT_FILE"
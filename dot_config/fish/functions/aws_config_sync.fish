function __aws_config_sync_get_regions
    # Static list of common regions
    echo us-east-1
    echo us-east-2
    echo us-west-1
    echo us-west-2
    echo af-south-1
    echo ap-east-1
    echo ap-south-1
    echo ap-northeast-1
    echo ap-northeast-2
    echo ap-northeast-3
    echo ap-southeast-1
    echo ap-southeast-2
    echo ca-central-1
    echo eu-central-1
    echo eu-west-1
    echo eu-west-2
    echo eu-west-3
    echo eu-south-1
    echo eu-north-1
    echo me-south-1
    echo sa-east-1
end

function aws_config_sync --description "Manage AWS credentials with 1Password integration"
    # Default tag and file paths
    set -l tag "TYPE:AWS_ACCESS_KEY"
    set -l output_file "$HOME/.aws/config"
    set -l credentials_file "$HOME/.aws/credentials"

    if test (count $argv) -eq 0
        echo "Usage: aws_config_sync COMMAND [options]"
        echo ""
        echo "Commands:"
        echo "  list       List AWS credentials stored in 1Password"
        echo "  sync       Sync credentials from 1Password to AWS config"
        echo "  get        Get specific profile credentials"
        echo "  create     Create a new AWS credential in 1Password"
        echo "  help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  aws_config_sync list                             # List all profiles"
        echo "  aws_config_sync list --filter prod               # List profiles containing 'prod'"
        echo "  aws_config_sync sync                             # Sync all profiles (credential process)"
        echo "  aws_config_sync sync --profile my-prof           # Sync specific profile"
        echo "  aws_config_sync sync --inline                    # Sync with inline credentials"
        echo "  aws_config_sync get my-profile                   # Get credentials for a profile"
        echo "  aws_config_sync create --account 123456789012    # Create a new credential"
        echo ""
        return 0
    end

    # Get the subcommand
    set -l cmd $argv[1]
    set -e argv[1]

    switch $cmd
        case "help"
            aws_config_sync
            return 0

        case "list"
            # Parse list arguments
            argparse 'v/verbose' 'f/filter=' 'r/region=' 'j/json' -- $argv
            or return 1

            set -l current_profile $AWS_PROFILE
            set -l current_region $AWS_DEFAULT_REGION

            # Get items with the specified tag
            set -l items (op item list --tags "$tag" --format json)
            
            # Check if items exist
            if test -z "$items"; or test "$items" = "[]"
                echo "No AWS profiles found in 1Password."
                return 0
            end

            # Apply region filter if specified
            if set -q _flag_region
                set items (echo "$items" | jq -c --arg region "REGION:$_flag_region" '[.[] | select(.tags[] | contains($region))]')
            end

            # Apply name filter if specified
            if set -q _flag_filter
                set items (echo "$items" | jq -c --arg filter "$_flag_filter" '[.[] | select(.title | contains($filter) or (.tags[] | select(startswith("TYPE:AWS_ACCESS_KEY/")) | contains($filter)))]')
            end

            # JSON output if requested
            if set -q _flag_json
                echo "$items"
                return 0
            end

            # Extract profile names for proper spacing calculation
            set -l profile_names
            echo "$items" | jq -c '.[]' | while read -l item
                set -l tag_value (echo "$item" | jq -r --arg tag "$tag" '.tags[] | select(startswith($tag + "/"))')
                set -l profile_name (echo "$tag_value" | sed "s/TYPE:AWS_ACCESS_KEY\///")
                set profile_names $profile_names $profile_name
            end

            # Print a table of profiles
            if set -q _flag_verbose
                printf "┌───────────────────┬────────────┬────────────────┬───────────────┬────────┐\n"
                printf "│ Profile           │ Region     │ Item Title     │ Vault         │ Current│\n"
                printf "├───────────────────┼────────────┼────────────────┼───────────────┼────────┤\n"
            else
                printf "┌───────────────────┬────────────┬───────────────┐\n"
                printf "│ Profile           │ Region     │ Status        │\n"
                printf "├───────────────────┼────────────┼───────────────┤\n"
            end

            # Process each item and display in table format
            echo "$items" | jq -c '.[]' | while read -l item
                set -l title (echo "$item" | jq -r '.title')
                set -l vault_name (echo "$item" | jq -r '.vault.name')
                set -l tag_value (echo "$item" | jq -r --arg tag "$tag" '.tags[] | select(startswith($tag + "/"))')
                set -l profile_name (echo "$tag_value" | sed "s/TYPE:AWS_ACCESS_KEY\///")
                set -l region (echo "$item" | jq -r '.tags[] | select(startswith("REGION:")) | sub("REGION:"; "")')
                
                if test -z "$region"; or test "$region" = "null"
                    set region "not set"
                end
                
                # Check if this is the current profile
                set -l current_marker " "
                if test "$AWS_PROFILE" = "$profile_name"
                    set current_marker "*"
                end
                
                # Format output with fixed width columns
                if set -q _flag_verbose
                    printf "│ %-17s │ %-10s │ %-14s │ %-13s │   %-4s │\n" $profile_name $region $title $vault_name $current_marker
                else
                    if test "$AWS_PROFILE" = "$profile_name" 
                        printf "│ %-17s │ %-10s │ %-13s │\n" $profile_name $region "CURRENT"
                    else
                        printf "│ %-17s │ %-10s │ %-13s │\n" $profile_name $region "available"
                    end
                end
            end

            # Close the table
            if set -q _flag_verbose
                printf "└───────────────────┴────────────┴────────────────┴───────────────┴────────┘\n"
            else
                printf "└───────────────────┴────────────┴───────────────┘\n"
            end

        case "sync"
            # Parse sync arguments
            argparse 'i/inline' 'p/profile=' -- $argv
            or return 1

            # Use inline credentials instead of credential process if requested
            set -l use_credential_process true
            if set -q _flag_inline
                set use_credential_process false
            end

            # Create or clear output files
            mkdir -p (dirname "$output_file")
            echo -n "" > "$output_file"
            echo -n "" > "$credentials_file"

            # Get items with the specified tag
            set -l items (op item list --tags "$tag" --format json)
            
            # Check if items exist
            if test -z "$items"; or test "$items" = "[]"
                echo "# No AWS profiles found" > "$output_file"
                return 0
            end

            # Filter by profile if specified
            if set -q _flag_profile
                set items (echo "$items" | jq -c --arg profile "$_flag_profile" --arg tag "$tag" '[.[] | select(.tags[] | select(startswith($tag + "/")) | contains($profile))]')
                
                if test -z "$items"; or test "$items" = "[]" -o "$items" = "null"
                    echo "No AWS profile found matching '$_flag_profile'."
                    return 1
                end
            end

            # Keep track of processed profiles
            set -l processed_count 0

            # Process each item and append to config
            echo "$items" | jq -c '.[]' | while read -l item
                set -l title (echo "$item" | jq -r '.title')
                set -l vault_name (echo "$item" | jq -r '.vault.name')
                set -l profile_name (echo "$item" | jq -r --arg tag "$tag" '.tags[] | select(startswith($tag + "/")) | sub($tag + "/"; "")')
                set -l region (echo "$item" | jq -r '.tags[] | select(startswith("REGION:")) | sub("REGION:"; "")')
                
                if test -z "$profile_name"
                    echo "Skipping item '$title': No profile name found in tags."
                    continue
                end
                
                set processed_count (math $processed_count + 1)
                
                if test "$use_credential_process" = true
                    # Write profile section using credential process
                    echo "[profile $profile_name]" >> "$output_file"
                    echo "credential_process = sh -c \"op item get '$title' --vault '$vault_name' --format json --reveal --fields label='AccessKeyId',label='SecretAccessKey' | jq 'map({key: .label, value: .value}) | from_entries + {Version: 1}'\"" >> "$output_file"
                else
                    # Get credentials directly from 1Password
                    set -l credentials (op item get "$title" --vault "$vault_name" --format json --reveal --fields label='AccessKeyId',label='SecretAccessKey')
                    set -l access_key (echo "$credentials" | jq -r '.[] | select(.label=="AccessKeyId") | .value')
                    set -l secret_key (echo "$credentials" | jq -r '.[] | select(.label=="SecretAccessKey") | .value')
                    
                    # Write to credentials file
                    echo "[$profile_name]" >> "$credentials_file"
                    echo "aws_access_key_id = $access_key" >> "$credentials_file"
                    echo "aws_secret_access_key = $secret_key" >> "$credentials_file"
                    echo "" >> "$credentials_file"
                    
                    # Write to config file
                    echo "[profile $profile_name]" >> "$output_file"
                end
                
                if test -n "$region"; and test "$region" != "null"
                    echo "region = $region" >> "$output_file"
                end
                
                echo "" >> "$output_file"
                
                echo "Processed profile: $profile_name"
            end

            echo "AWS config generated at $output_file with $processed_count profiles"
            if test "$use_credential_process" = false
                echo "AWS credentials generated at $credentials_file"
            end

        case "get"
            if test (count $argv) -lt 1
                echo "Error: Missing profile name. Usage: aws_config_sync get PROFILE_NAME"
                return 1
            end
            
            set -l target_profile $argv[1]
            set -l found false
            
            # Get items with the specified tag
            set -l items (op item list --tags "$tag" --format json)
            
            # Check if items exist
            if test -z "$items"; or test "$items" = "[]"
                echo "No AWS profiles found in 1Password."
                return 1
            end
            
            # Process each item to find the requested profile
            echo "$items" | jq -c '.[]' | while read -l item
                set -l title (echo "$item" | jq -r '.title')
                set -l vault_name (echo "$item" | jq -r '.vault.name')
                set -l profile_name (echo "$item" | jq -r --arg tag "$tag" '.tags[] | select(startswith($tag + "/")) | sub($tag + "/"; "")')
                
                if test "$profile_name" = "$target_profile"
                    set found true
                    set -l credentials (op item get "$title" --vault "$vault_name" --format json --reveal --fields label='AccessKeyId',label='SecretAccessKey')
                    set -l access_key (echo "$credentials" | jq -r '.[] | select(.label=="AccessKeyId") | .value')
                    set -l secret_key (echo "$credentials" | jq -r '.[] | select(.label=="SecretAccessKey") | .value')
                    
                    echo "# AWS credentials for profile: $profile_name"
                    echo "export AWS_ACCESS_KEY_ID=$access_key"
                    echo "export AWS_SECRET_ACCESS_KEY=$secret_key"
                    
                    # Try to copy to clipboard if available
                    set -l clipboard_cmd ""
                    if command -v pbcopy >/dev/null 2>&1
                        set clipboard_cmd "pbcopy"
                    else if command -v xclip >/dev/null 2>&1
                        set clipboard_cmd "xclip -selection clipboard"
                    end
                    
                    if test -n "$clipboard_cmd"
                        echo -e "export AWS_ACCESS_KEY_ID=$access_key\nexport AWS_SECRET_ACCESS_KEY=$secret_key" | eval $clipboard_cmd
                        echo "# Credentials copied to clipboard"
                    end
                    
                    break
                end
            end
            
            if test "$found" = false
                echo "Error: Profile '$target_profile' not found."
                return 1
            end

        case "create"
            # Parse create arguments
            argparse 'a/account=' 'u/user=' 'r/region=' 'v/vault=' 'o/org=' -- $argv
            or return 1
            
            # Check for account ID (required)
            if not set -q _flag_account
                echo "Error: Account ID is required. Usage: aws_config_sync create --account ACCOUNT_ID"
                return 1
            end
            
            # Validate account ID format
            if not string match -qr '^[0-9]{12}$' $_flag_account
                echo "Warning: Account ID should be a 12-digit number. Continuing anyway."
            end
            
            # Set default values
            set -l account_id $_flag_account
            set -l user_type "root"
            set -l region "us-east-1"
            set -l vault "dev"
            set -l org_tag ""
            
            # Override defaults if specified
            if set -q _flag_user
                set user_type "user/$_flag_user"
            end
            
            if set -q _flag_region
                set region $_flag_region
            end
            
            if set -q _flag_vault
                set vault $_flag_vault
            end
            
            if set -q _flag_org
                set org_tag "ORG:$_flag_org"
            end
            
            # Format principal for tag
            set -l principal $user_type
            if string match -q "user/*" $user_type
                set principal (string replace "user/" "user:" $user_type)
            end
            
            # Generate item title
            set -l title "$account_id:$user_type"
            
            # Generate tags
            set -l tags "REGION:$region" "TYPE:AWS_ACCESS_KEY/$account_id/$principal"
            if test -n "$org_tag"
                set tags $tags $org_tag
            end
            
            # Generate a random credential for initial creation
            set -l random_access_key (random 20 | md5sum | string sub -l 20 | string upper)
            set -l random_secret_key (random 40 | md5sum | string sub -l 40)
            
            # Create temporary JSON file for the new item
            set -l temp_file (mktemp)
            
            # Create JSON structure
            echo '{
  "title": "'$title'",
  "category": "API_CREDENTIAL",
  "fields": [
    {
      "id": "access_key",
      "type": "CONCEALED",
      "purpose": "USERNAME",
      "label": "AccessKeyId",
      "value": "'$random_access_key'"
    },
    {
      "id": "secret_key",
      "type": "CONCEALED",
      "purpose": "PASSWORD",
      "label": "SecretAccessKey",
      "value": "'$random_secret_key'"
    }
  ],
  "tags": '(echo $tags | jq -R -s 'split(" ")' | tr -d '\n')' 
}' > $temp_file
            
            # Create the item in 1Password
            set -l result (op item create --vault $vault --format json (cat $temp_file) 2>&1)
            set -l status $status
            
            # Clean up temp file
            rm $temp_file
            
            # Check result
            if test $status -eq 0
                echo "Created AWS credential in 1Password:"
                echo "  Title:   $title"
                echo "  Profile: $account_id/$principal"
                echo "  Region:  $region"
                echo "  Vault:   $vault"
                echo ""
                echo "IMPORTANT: Update with actual credentials using 1Password UI."
                echo "The item was created with placeholder credentials."
            else
                echo "Error creating AWS credential in 1Password:"
                echo $result
                return 1
            end

        case "*"
            echo "Error: Unknown command '$cmd'"
            aws_config_sync
            return 1
    end
end

# Completions for aws_config_sync
# Main commands
complete -f -c aws_config_sync -n "__fish_use_subcommand" -a "list" -d "List AWS credentials stored in 1Password"
complete -f -c aws_config_sync -n "__fish_use_subcommand" -a "sync" -d "Sync credentials from 1Password to AWS config"
complete -f -c aws_config_sync -n "__fish_use_subcommand" -a "get" -d "Get specific profile credentials"
complete -f -c aws_config_sync -n "__fish_use_subcommand" -a "create" -d "Create a new AWS credential in 1Password"
complete -f -c aws_config_sync -n "__fish_use_subcommand" -a "help" -d "Show help message"

# Options for 'list' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s v -l verbose -d "Show detailed information"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s f -l filter -d "Filter profiles by name pattern"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s r -l region -d "Filter profiles by region"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s j -l json -d "Output in JSON format"

# Options for 'sync' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from sync" -s i -l inline -d "Store credentials directly in ~/.aws/credentials"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from sync" -s p -l profile -d "Sync only specific profile"

# Options for 'create' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create" -s a -l account -d "AWS account ID (12 digits)"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create" -s u -l user -d "Username (omit for root)"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create" -s r -l region -d "AWS region (default: us-east-1)"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create" -s v -l vault -d "1Password vault (default: dev)"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create" -s o -l org -d "Organization tag"

# Region completion for 'create' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create; and string match -q -- '--region' (commandline -ct); or string match -q -- '-r' (commandline -ct)" -a "(__aws_config_sync_get_regions)"

# Vault completion for 'create' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from create; and string match -q -- '--vault' (commandline -ct); or string match -q -- '-v' (commandline -ct)" -a "(op vault list --format json | jq -r '.[].name')"

# Profile name completion for 'get' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from get; and test (count (commandline -opc)) -eq 2" -a "(aws_config_sync list -j | jq -r '.[] | .tags[] | select(startswith(\"TYPE:AWS_ACCESS_KEY/\")) | sub(\"TYPE:AWS_ACCESS_KEY/\"; \"\")' 2>/dev/null)" -d "AWS Profile"
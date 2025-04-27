function __aws_config_sync_get_regions
    # Try to fetch regions dynamically using AWS CLI
    if command -v aws >/dev/null 2>&1
        aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n' | sort
    else
        # Fallback to static list
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
        echo "  aws_config_sync list --account 123456789012      # List profiles for specific account"
        echo "  aws_config_sync list --region us-east-1          # List profiles in specific region"
        echo "  aws_config_sync list --org myorg                 # List profiles for specific organization"
        echo "  aws_config_sync sync                             # Sync all profiles (credential process)"
        echo "  aws_config_sync sync --profile my-prof           # Sync specific profile"
        echo "  aws_config_sync sync --inline                    # Sync with inline credentials"
        echo "  aws_config_sync get my-profile                   # Get credentials for a profile"
        echo "  aws_config_sync create                           # Create a new credential (interactive)"
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
            argparse 'v/verbose' 'a/account=' 'r/region=' 'o/org=' 'j/json' -- $argv
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

            # Apply account ID filter if specified
            if set -q _flag_account
                set items (echo "$items" | jq -c --arg account "$_flag_account" '[.[] | select(.tags[] | select(startswith("TYPE:AWS_ACCESS_KEY/")) | contains($account))]')
            end

            # Apply organization filter if specified
            if set -q _flag_org
                set items (echo "$items" | jq -c --arg org "ORG:$_flag_org" '[.[] | select(.tags[] | contains($org))]')
            end

            # JSON output if requested
            if set -q _flag_json
                echo "$items"
                return 0
            end

            # First pass: determine maximum column widths
            set -l max_profile_len 7 # Minimum width for "Profile"
            set -l max_region_len 6 # Minimum width for "Region"
            set -l max_org_len 12 # Minimum width for "Organization"
            set -l max_title_len 10 # Minimum width for "Item Title"
            set -l max_vault_len 5 # Minimum width for "Vault"
            set -l max_status_len 6 # Minimum width for "Status"
            set -l max_current_len 7 # Minimum width for "Current"

            echo "$items" | jq -c '.[]' | while read -l item
                set -l title (echo "$item" | jq -r '.title')
                set -l vault_name (echo "$item" | jq -r '.vault.name')
                set -l tag_value (echo "$item" | jq -r --arg tag "$tag" '.tags[] | select(startswith($tag + "/"))')
                set -l profile_name (echo "$tag_value" | sed "s/TYPE:AWS_ACCESS_KEY\///")
                set -l region (echo "$item" | jq -r '.tags[] | select(startswith("REGION:")) | sub("REGION:"; "")')
                set -l org (echo "$item" | jq -r '.tags[] | select(startswith("ORG:")) | sub("ORG:"; "")')
                
                if test -z "$region"; or test "$region" = "null"
                    set region "not set"
                end
                
                if test -z "$org"; or test "$org" = "null"
                    set org "not set"
                end

                # Update max lengths
                set -l profile_len (string length "$profile_name")
                if test $profile_len -gt $max_profile_len
                    set max_profile_len $profile_len
                end
                
                set -l region_len (string length "$region")
                if test $region_len -gt $max_region_len
                    set max_region_len $region_len
                end
                
                set -l org_len (string length "$org")
                if test $org_len -gt $max_org_len
                    set max_org_len $org_len
                end
                
                set -l title_len (string length "$title")
                if test $title_len -gt $max_title_len
                    set max_title_len $title_len
                end
                
                set -l vault_len (string length "$vault_name")
                if test $vault_len -gt $max_vault_len
                    set max_vault_len $vault_len
                end
                
                # Set status length (needed for both verbose and non-verbose)
                set -l status_len
                if test "$AWS_PROFILE" = "$profile_name"
                    set status_len (string length "CURRENT")
                else
                    set status_len (string length "available")
                end
                if test $status_len -gt $max_status_len
                    set max_status_len $status_len
                end
                
                # Current marker length is always 1 character
                if test 7 -gt $max_current_len # 7 is the length of "Current"
                    set max_current_len 7
                end
            end

            # Add padding to column widths
            set max_profile_len (math "$max_profile_len + 2")
            set max_region_len (math "$max_region_len + 2")
            set max_org_len (math "$max_org_len + 2")
            set max_title_len (math "$max_title_len + 2")
            set max_vault_len (math "$max_vault_len + 2")
            set max_status_len (math "$max_status_len + 2")

            # Create border strings
            set -l profile_border (string repeat -n (math "$max_profile_len + 2") "─")
            set -l region_border (string repeat -n (math "$max_region_len + 2") "─")
            set -l org_border (string repeat -n (math "$max_org_len + 2") "─")
            set -l title_border (string repeat -n (math "$max_title_len + 2") "─")
            set -l vault_border (string repeat -n (math "$max_vault_len + 2") "─")
            set -l status_border (string repeat -n (math "$max_status_len + 2") "─")
            set -l current_border (string repeat -n 9 "─")

            # Print a table of profiles with dynamic widths
            if set -q _flag_verbose
                # Create format strings for table headers and borders
                set -l header_format "│ %-"$max_profile_len"s │ %-"$max_region_len"s │ %-"$max_org_len"s │ %-"$max_title_len"s │ %-"$max_vault_len"s │ %-"$max_status_len"s │ %-7s │"
                
                # Print top border
                echo "┌$profile_border┬$region_border┬$org_border┬$title_border┬$vault_border┬$status_border┬$current_border┐"
                printf "$header_format\n" "Profile" "Region" "Organization" "Item Title" "Vault" "Status" "Current"
                echo "├$profile_border┼$region_border┼$org_border┼$title_border┼$vault_border┼$status_border┼$current_border┤"
            else
                # Create format strings for table headers and borders
                set -l header_format "│ %-"$max_profile_len"s │ %-"$max_region_len"s │ %-"$max_org_len"s │ %-"$max_status_len"s │"
                
                # Print top border
                echo "┌$profile_border┬$region_border┬$org_border┬$status_border┐"
                printf "$header_format\n" "Profile" "Region" "Organization" "Status"
                echo "├$profile_border┼$region_border┼$org_border┼$status_border┤"
            end

            # Process each item and display in table format with dynamic widths
            echo "$items" | jq -c '.[]' | while read -l item
                set -l title (echo "$item" | jq -r '.title')
                set -l vault_name (echo "$item" | jq -r '.vault.name')
                set -l tag_value (echo "$item" | jq -r --arg tag "$tag" '.tags[] | select(startswith($tag + "/"))')
                set -l profile_name (echo "$tag_value" | sed "s/TYPE:AWS_ACCESS_KEY\///")
                set -l region (echo "$item" | jq -r '.tags[] | select(startswith("REGION:")) | sub("REGION:"; "")')
                set -l org (echo "$item" | jq -r '.tags[] | select(startswith("ORG:")) | sub("ORG:"; "")')
                
                if test -z "$region"; or test "$region" = "null"
                    set region "not set"
                end
                
                if test -z "$org"; or test "$org" = "null"
                    set org "not set"
                end
                
                # Check if this is the current profile
                set -l current_marker ""
                set -l profile_status "available"
                if test "$AWS_PROFILE" = "$profile_name"
                    set current_marker "*"
                    set profile_status "CURRENT"
                end
                
                # Format output with dynamic width columns
                if set -q _flag_verbose
                    set -l row_format "│ %-"$max_profile_len"s │ %-"$max_region_len"s │ %-"$max_org_len"s │ %-"$max_title_len"s │ %-"$max_vault_len"s │ %-"$max_status_len"s │ %-7s │"
                    printf "$row_format\n" $profile_name $region $org $title $vault_name $profile_status $current_marker
                else
                    set -l row_format "│ %-"$max_profile_len"s │ %-"$max_region_len"s │ %-"$max_org_len"s │ %-"$max_status_len"s │"
                    printf "$row_format\n" $profile_name $region $org $profile_status
                end
            end

            # Close the table with dynamic widths
            if set -q _flag_verbose
                echo "└$profile_border┴$region_border┴$org_border┴$title_border┴$vault_border┴$status_border┴$current_border┘"
            else
                echo "└$profile_border┴$region_border┴$org_border┴$status_border┘"
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
                    
                    echo "export AWS_ACCESS_KEY_ID=$access_key"
                    echo "export AWS_SECRET_ACCESS_KEY=$secret_key"
                    
                    set -l clipboard_cmd ""
                    if command -v pbcopy >/dev/null 2>&1
                        set clipboard_cmd "pbcopy"
                    else if command -v xclip >/dev/null 2>&1
                        set clipboard_cmd "xclip -selection clipboard"
                    end
                    
                    if test -n "$clipboard_cmd"
                       echo -e "export AWS_ACCESS_KEY_ID=$access_key\nexport AWS_SECRET_ACCESS_KEY=$secret_key" | eval $clipboard_cmd
                    end
                    
                    break
                end
            end
            
            if test "$found" = false
                echo "Error: Profile '$target_profile' not found."
                return 1
            end

        case "create"
            # Prompt for AWS access key ID
            echo "Enter AWS Access Key ID:"
            read -s access_key
            if test -z "$access_key"
                echo "Error: Access Key ID is required."
                return 1
            end
            echo "Access Key ID received"
            
            # Prompt for AWS secret access key
            echo "Enter AWS Secret Access Key:"
            read -s secret_key
            if test -z "$secret_key"
                echo "Error: Secret Access Key is required."
                return 1
            end
            echo "Secret Access Key received"
            
            # Set temporary AWS credentials for STS call
            set -gx AWS_ACCESS_KEY_ID $access_key
            set -gx AWS_SECRET_ACCESS_KEY $secret_key
            
            # Call get-caller-identity to validate the credentials and get user/account info
            set -l sts_result (aws sts get-caller-identity --output json 2>&1)
            set -l sts_status $status
            
            if test $sts_status -ne 0
                echo "Error validating AWS credentials:"
                echo $sts_result
                set -e AWS_ACCESS_KEY_ID
                set -e AWS_SECRET_ACCESS_KEY
                return 1
            end
            
            # Extract account ID and user type from STS response
            set -l account_id (echo $sts_result | jq -r '.Account')
            set -l user_arn (echo $sts_result | jq -r '.Arn')
            
            echo "Account ID: $account_id"
            echo "User ARN: $user_arn"
            # Determine if this is a root or IAM user
            set -l user_type "root"
            set -l principal "root"
            
            if string match -q "*:user/*" $user_arn
                set user_type "user/"(echo $user_arn | sed -n 's/.*:user\/\([^:]*\).*/\1/p')
                set principal "user:"(echo $user_arn | sed -n 's/.*:user\/\([^:]*\).*/\1/p')
            end
            
            echo "User type: $user_type"
            echo "Principal: $principal"

            # Try to get organization info
            set -l org ""
            set -l org_result (aws organizations describe-organization --output json 2>/dev/null)
            set -l org_status $status
            
            if test $org_status -eq 0
                set org (echo $org_result | jq -r '.Organization.Id')
            else
                # Prompt for organization if AWS CLI failed
                echo "Enter organization ID (leave empty to skip):"
                read input_org
                if test -n "$input_org"
                    set org $input_org
                end
            end
            
            # Prompt for AWS region
            echo "Enter AWS region (default: us-east-1):"
            read input_region
            set -l region "us-east-1"
            if test -n "$input_region"
                set region $input_region
            end
            
            # Prompt for 1Password vault
            echo "Enter 1Password vault name (default: dev):"
            read input_vault
            set -l vault "dev"
            if test -n "$input_vault"
                set vault $input_vault
            end
            
            # Clean up temporary AWS environment variables
            set -e AWS_ACCESS_KEY_ID
            set -e AWS_SECRET_ACCESS_KEY
            
            # Generate item title
            set -l title "$account_id:$user_type"
            
            # Generate tags as comma-separated string for 1Password CLI
            set -l tags_str (string join , "REGION:$region" "TYPE:AWS_ACCESS_KEY/$account_id/$principal")
            if test -n "$org"
                set tags_str "$tags_str,ORG:$org"
            end
            
            # Create the item in 1Password
            set -l op_result (op item create \
                --vault "$vault" \
                --category "API Credential" \
                --title "$title" \
                --tags "$tags_str" \
                "AccessKeyId[concealed]=$access_key" \
                "SecretAccessKey[concealed]=$secret_key" \
                --format json 2>&1)
            set -l op_status $status
            set -l op_item (echo $op_result | jq -r '.id')
            
            # Check result
            if test $op_status -eq 0
                op item edit $op_item --vault $vault  \
                  "type[delete]" \
                  "hostname[delete]" \
                  "username[delete]" \
                  "credential[delete]" \
                  "filename[delete]" \
                  "valid from[delete]" \
                  "expires[delete]" 

                echo "Created AWS credential in 1Password:"
                echo "  Title:   $title"
                echo "  Profile: $account_id/$principal"
                echo "  Region:  $region"
                if test -n "$org"
                    echo "  Org:     $org"
                end
                echo "  Vault:   $vault"
            else
                echo "Error creating AWS credential in 1Password:"
                echo $op_result
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
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s a -l account -d "Filter by AWS account ID"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s r -l region -d "Filter by AWS region"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s o -l org -d "Filter by organization"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list" -s j -l json -d "Output in JSON format"

# Options for 'sync' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from sync" -s i -l inline -d "Store credentials directly in ~/.aws/credentials"
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from sync" -s p -l profile -d "Sync only specific profile"

# Region completion
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from list; and string match -q -- '--region' (commandline -ct); or string match -q -- '-r' (commandline -ct)" -a "(__aws_config_sync_get_regions)"

# Vault completion
complete -f -c aws_config_sync -n "__fish_contains_opt -s v vault create; or __fish_contains_opt -s v vault" -a "(op vault list --format json | jq -r '.[].name')"

# Profile name completion for 'get' command
complete -f -c aws_config_sync -n "__fish_seen_subcommand_from get; and test (count (commandline -opc)) -eq 2" -a "(aws_config_sync list -j | jq -r '.[] | .tags[] | select(startswith(\"TYPE:AWS_ACCESS_KEY/\")) | sub(\"TYPE:AWS_ACCESS_KEY/\"; \"\")' 2>/dev/null)" -d "AWS Profile"
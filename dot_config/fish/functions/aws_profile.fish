function aws_profile --description "Manage AWS profile and region settings"
    set -l cmd_help "
Usage: aws_profile [command]

Commands:
  current        Show current profile and region
  list           List all available profiles
  use PROFILE    Switch to a specific profile
  region REGION  Set the AWS region
  help           Show this help message
"

    # No arguments or help command - show current settings or help
    if test (count $argv) -eq 0
        echo $cmd_help
        return 0
    end

    # Process subcommands
    switch $argv[1]
        case "current"
            echo "Current AWS profile settings:"
            echo "  Profile: $AWS_PROFILE"
            echo "  Region:  $AWS_DEFAULT_REGION"
            return 0
        case "list"
            echo "Available AWS profiles:"
            for profile in (__aws_profile_get_profiles)
                if test "$profile" = "$AWS_PROFILE"
                    echo "* $profile (current)"
                else
                    echo "  $profile"
                end
            end

        case "use"
            if test (count $argv) -lt 2
                echo "Error: Missing profile name. Usage: aws_profile use PROFILE" >&2
                return 1
            end
            
            # Warn about extra arguments
            if test (count $argv) -gt 2
                echo "Warning: Ignoring extra arguments. Usage: aws_profile use PROFILE" >&2
            end
            
            set -gx AWS_PROFILE $argv[2]
            echo "Switched to AWS profile: $argv[2]"
            
            # Keep existing region if set, otherwise use default
            if test -z "$AWS_DEFAULT_REGION"
                set -gx AWS_DEFAULT_REGION us-east-1
                echo "Region set to default: us-east-1"
            end

        case "region"
            if test (count $argv) -lt 2
                echo "Error: Missing region name. Usage: aws_profile region REGION" >&2
                return 1
            end
            
            # Warn about extra arguments
            if test (count $argv) -gt 2
                echo "Warning: Ignoring extra arguments. Usage: aws_profile region REGION" >&2
            end
            
            set -gx AWS_DEFAULT_REGION $argv[2]
            echo "AWS region set to: $argv[2]"
            
            # Let the user know if no profile is set
            if test -z "$AWS_PROFILE"
                echo "Note: No AWS profile is currently set. Use 'aws_profile use PROFILE' to set one."
            end

        case "*"
            echo "Error: Unknown command '$argv[1]'" >&2
            echo $cmd_help
            return 1
    end
end

# Helper functions for completions
function __aws_profile_get_profiles
    # Combine profiles from credentials and config, removing duplicates
    cat ~/.aws/credentials 2>/dev/null | grep '^\[' | sed 's/^\[//;s/\]$//' | sort -u
    cat ~/.aws/config 2>/dev/null | grep '^\[profile ' | sed 's/^\[profile //;s/\]$//' | sort -u
end

function __aws_profile_get_regions
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

complete -f -c aws_profile
complete -f -c aws_profile -n "__fish_use_subcommand" -a "list" -d "List all available profiles"
complete -f -c aws_profile -n "__fish_use_subcommand" -a "use" -d "Switch to a specific profile"
complete -f -c aws_profile -n "__fish_use_subcommand" -a "region" -d "Set the AWS region"
complete -f -c aws_profile -n "__fish_use_subcommand" -a "help" -d "Show help"
complete -f -c aws_profile -n "__fish_use_subcommand" -a "current" -d "Show current profile and region"
complete -f -c aws_profile -n "__fish_seen_subcommand_from use; and test (count (commandline -opc)) -eq 2" -a "(__aws_profile_get_profiles)" -d "AWS Profile"
complete -f -c aws_profile -n "__fish_seen_subcommand_from region; and test (count (commandline -opc)) -eq 2" -a "(__aws_profile_get_regions)" -d "AWS Region"


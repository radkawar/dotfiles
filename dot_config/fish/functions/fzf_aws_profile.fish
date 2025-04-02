function fzf_aws_profile --description "Insert AWS profile using fzf"
    # Define cache file
    set -l cache_file ~/.cache/aws_profiles_cache
    set -l refresh_cache false

    # Check if user wants to force refresh the cache
    if contains -- --refresh $argv
        set refresh_cache true
    end

    # Always rebuild cache if refresh is requested, regardless of command context
    if test "$refresh_cache" = true
        mkdir -p (dirname $cache_file)
        echo "Building AWS profile cache..." >&2

        # Get profile names
        set -l profiles (cat ~/.aws/credentials ~/.aws/config 2>/dev/null | grep '^\[' | tr -d '[]' | sed 's/profile //' | sort -u)

        # Clear cache file
        echo "" >$cache_file

        # Get info for each profile
        for profile in $profiles
            set -l region (aws configure get region --profile $profile 2>/dev/null || echo "-")

            # Try to get account info (without a pipe to prevent status issues)
            aws sts get-caller-identity --profile $profile >/tmp/aws_profile_info.tmp 2>/dev/null
            set -l aws_status $status

            if test $aws_status -eq 0
                set -l userid (jq -r '.UserId' < /tmp/aws_profile_info.tmp 2>/dev/null || echo "-")
                set -l account (jq -r '.Account' < /tmp/aws_profile_info.tmp 2>/dev/null || echo "-")
                set -l arn (jq -r '.Arn' < /tmp/aws_profile_info.tmp 2>/dev/null || echo "-")

                # Make sure no field is empty
                test -z "$userid" && set userid -
                test -z "$account" && set account -
                test -z "$region" && set region -
                test -z "$arn" && set arn -

                # Format properly with tabs to ensure column alignment
                printf "%s\t%s\t%s\t%s\t%s\n" $profile $userid $account $region $arn >>$cache_file
            else
                # Fallback if we can't get account info
                printf "%s\t%s\t%s\t%s\t%s\n" $profile - - $region - >>$cache_file
            end
        end

        # Clean up temp file
        rm -f /tmp/aws_profile_info.tmp

        echo "Cache built successfully!" >&2
        return 0
    end

    # Check if commandline contains aws - only needed for profile selection
    if string match -q -- "*aws*" (commandline)
        # Only show if no profile is already specified
        if not string match -q -- "*--profile*" (commandline)
            # Build cache if it doesn't exist
            if test ! -f "$cache_file"
                # Call ourselves with the refresh flag
                fzf_aws_profile --refresh
            end

            # Display profiles if cache exists
            if test -f "$cache_file"
                # Create a header that matches the tabular format
                printf "Profile\tUserID\tAccount\tRegion\tARN\n" >/tmp/aws_profile_header.tmp
                cat /tmp/aws_profile_header.tmp $cache_file | column -t -s \t >/tmp/aws_profile_display.tmp

                # Use fzf with the properly formatted display file
                set -l selected_line (cat /tmp/aws_profile_display.tmp | fzf --height 40% --reverse --header-lines=1)

                # Clean up temp files
                rm -f /tmp/aws_profile_header.tmp /tmp/aws_profile_display.tmp

                if test -n "$selected_line"
                    # Extract just the profile name (first column)
                    set -l selected_profile (string split -f1 " " -- "$selected_line")
                    if test -n "$selected_profile"
                        # Insert the profile option at the cursor position
                        commandline -i " --profile $selected_profile"
                    end
                end
            else
                echo "No AWS profiles found or cache not built" >&2
            end
        end
    end
end

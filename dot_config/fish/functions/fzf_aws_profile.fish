function fzf_aws_profile --description "Insert AWS profile using fzf"
    set -l cache_file ~/.cache/aws_profiles_cache
    set -l refresh_cache false

    if contains -- --refresh $argv
        set refresh_cache true
    end

    if test "$refresh_cache" = true
        mkdir -p (dirname $cache_file)
        echo "Building AWS profile cache..." >&2
        set -l profiles (cat ~/.aws/credentials ~/.aws/config 2>/dev/null | grep '^\[' | tr -d '[]' | sed 's/profile //' | sort -u)
        echo "" >$cache_file
        for profile in $profiles
            set -l region (aws configure get region --profile $profile 2>/dev/null || echo "-")
            aws sts get-caller-identity --profile $profile >/tmp/aws_profile_info.tmp 2>/dev/null
            set -l aws_status $status
            if test $aws_status -eq 0
                set -l userid (jq -r '.UserId' < /tmp/aws_profile_info.tmp 2>/dev/null || echo "-")
                set -l account (jq -r '.Account' < /tmp/aws_profile_info.tmp 2>/dev/null || echo "-")
                set -l arn (jq -r '.Arn' < /tmp/aws_profile_info.tmp 2>/dev/null || echo "-")
                test -z "$userid" && set userid -
                test -z "$account" && set account -
                test -z "$region" && set region -
                test -z "$arn" && set arn -
                printf "%s\t%s\t%s\t%s\t%s\n" $profile $userid $account $region $arn >>$cache_file
            else
                printf "%s\t%s\t%s\t%s\t%s\n" $profile - - $region - >>$cache_file
            end
        end
        rm -f /tmp/aws_profile_info.tmp
        echo "Cache built successfully!" >&2
        return 0
    end

    if test ! -f "$cache_file"
        fzf_aws_profile --refresh
    end

    if test -f "$cache_file"
        printf "Profile\tUserID\tAccount\tRegion\tARN\n" >/tmp/aws_profile_header.tmp
        cat /tmp/aws_profile_header.tmp $cache_file | column -t -s \t >/tmp/aws_profile_display.tmp
        set -l selected_line (cat /tmp/aws_profile_display.tmp | fzf --height 40% --reverse --header-lines=1)
        rm -f /tmp/aws_profile_header.tmp /tmp/aws_profile_display.tmp
        if test -n "$selected_line"
            set -l selected_profile (string split -f1 " " -- "$selected_line")
            if test -n "$selected_profile"
                commandline -i " --profile $selected_profile"
            end
        end
    else
        echo "No AWS profiles found or cache not built" >&2
    end
end

function fish_prompt
    printf "\033]0;%s\007" (pwd)
    
    # Get prompt style (default to two-line if not set)
    set -l prompt_style two-line
    if set -q FISH_PROMPT_STYLE
        set prompt_style $FISH_PROMPT_STYLE
    end
    
    # Detect OS
    set os (uname)
    # Get IP
    if test "$os" = Darwin
        set ip (ipconfig getifaddr en0 2>/dev/null)
    else if test "$os" = Linux
        set ip (hostname -I | awk '{print $1}' 2>/dev/null)
    else
        set ip unknown
    end
    if test -z "$ip"
        set ip no-ip
    end
    
    # First char of username
    set initial (whoami | cut -c1)
    # Current time
    set time (date "+%T")
    # Current date
    set date_str (date "+%m/%d")
    
    # Get shortened path: /U/D/dev → full last folder
    set full_path (pwd)
    set home (echo $HOME)
    if string match -q "$home*" $full_path
        set full_path "~"(string replace "$home" "" $full_path)
    end
    set parts (string split "/" $full_path)
    set shortened_path ""
    for i in (seq (count $parts))
        set part $parts[$i]
        if test $i -lt (count $parts)
            if test -n "$part"
                set shortened_path "$shortened_path/"(string sub -l 1 $part)
            end
        else
            set shortened_path "$shortened_path/$part"
        end
    end
    
    # Git branch and status
    set git_info ""
    if type -q git
        set branch (command git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if test -n "$branch"
            # Check if there are uncommitted changes
            set git_status (command git status --porcelain 2>/dev/null)
            if test -n "$git_status"
                set git_info " "(set_color magenta)"[$branch*]"
            else
                set git_info " "(set_color magenta)"[$branch]"
            end
        end
    end

    # AWS Profile info - format long profiles nicely
    set aws_info ""
    if set -q AWS_PROFILE
        # Handle long AWS profile names like "000000000000/root" or "000000000000/user:dummy"
        if string match -q "*/*" $AWS_PROFILE
            set parts (string split "/" $AWS_PROFILE)
            set account $parts[1]
            set role $parts[2]
            # Abbreviate long account numbers: 307946636109 -> 307...109
            if test (string length $account) -gt 8
                set account_short (string sub -l 3 $account)"..."(string sub -s -3 $account)
                set aws_info " "(set_color yellow)"[$account_short/$role]"
            else
                set aws_info " "(set_color yellow)"[$AWS_PROFILE]"
            end
        else
            set aws_info " "(set_color yellow)"[$AWS_PROFILE]"
        end
    end

    # Get terminal width
    set term_width (tput cols)

    # Display last command status if it's non-zero
    set last_status $status
    set status_string ""
    if test $last_status -ne 0
        set status_string " "(set_color red)"✗ $last_status"
    else
        set status_string " "(set_color green)"✓"
    end

    # Display command duration if it's significant
    set duration_string ""
    if test -n "$CMD_DURATION" -a "$CMD_DURATION" -gt 1000 # Threshold: 1000ms
        # Format duration (e.g., 1.2s)
        set duration_s (math --scale=1 "$CMD_DURATION / 1000")
        set duration_string " "(set_color blue)"⏱ $duration_s"s""
    end

    # Build prompt based on style
    switch $prompt_style
        case "single-line" "compact"
            # Original single-line style - clean, status/duration moved to right prompt
            if test $term_width -lt 120
                echo -n (set_color cyan)"[$time]" (set_color yellow)" $shortened_path"$git_info (set_color normal)"❯ "
            else
                echo -n (set_color cyan)"[$time]" (set_color green)" $initial@$ip" (set_color yellow)" $shortened_path"$git_info (set_color normal)"❯ "
            end
            
        case "minimal"
            # Minimal single-line style - no time, just essentials
            echo -n (set_color blue)(basename $full_path)$git_info (set_color normal)"❯ "
            
        case "*"
            # Two-line style (default) - clean and consistent
            # First line: core info
            echo -n (set_color cyan)"┌─[" (set_color white)"$time" (set_color cyan)"]"
            if test $term_width -ge 100
                echo -n (set_color cyan)"─[" (set_color green)"$initial@$ip" (set_color cyan)"]"
            end
            echo -n (set_color cyan)"─[" (set_color yellow)"$shortened_path" (set_color cyan)"]"
            if test -n "$git_info"
                echo -n $git_info
            end
            
            # Right side info - only show what's relevant
            set -l info_parts
            if test -n "$duration_string"
                set info_parts $info_parts $duration_string
            end
            if test $last_status -ne 0
                set info_parts $info_parts " "(set_color red)"✗"
            end
            
            if test (count $info_parts) -gt 0
                for part in $info_parts
                    echo -n $part
                end
            end
            
            echo (set_color normal)
            
            # Second line: clean input prompt
            echo -n (set_color cyan)"└─❯ "(set_color normal)
    end
end

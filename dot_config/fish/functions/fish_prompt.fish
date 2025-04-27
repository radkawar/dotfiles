function fish_prompt
    printf "\033]0;%s\007" (pwd)
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
    # Git branch
    set git_branch ""
    if type -q git
        set branch (command git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if test -n "$branch"
            set git_branch " "(set_color magenta)"[$branch]"
        end
    end

    # Get terminal width
    set term_width (tput cols)

    # Build the prompt based on terminal width
    if test $term_width -lt 120
        # Narrow terminal: omit date and hostname
        set prompt_first_part (set_color cyan)"[$time]" (set_color yellow) "$shortened_path" $git_branch
    else
        # Wide terminal: include date and hostname
        set prompt_first_part (set_color cyan)"[$time]" (set_color green)" $initial@$ip" (set_color yellow)" $shortened_path" $git_branch
    end

    # Display last command status if it's non-zero
    set last_status $status
    set status_string ""
    if test $last_status -ne 0
        set status_string " "(set_color red)"($last_status)"
    end

    # Display command duration if it's significant
    set duration_string ""
    if test -n "$CMD_DURATION" -a "$CMD_DURATION" -gt 1000 # Threshold: 1000ms
        # Format duration (e.g., 1.2s)
        set duration_s (math --scale=1 "$CMD_DURATION / 1000")
        set duration_string " "(set_color blue)"($duration_s"s")"
    end

    echo -n $prompt_first_part $status_string $duration_string (set_color normal)"❯ "
end

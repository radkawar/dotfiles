function fish_prompt
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

    # Final prompt
    echo -n (set_color cyan)"[$time]" (set_color green)" $initial@$ip" (set_color yellow)" $shortened_path" $git_branch (set_color normal)" ❯ "
end

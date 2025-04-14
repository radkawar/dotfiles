# ~/.config/fish/completions/asg.fish
function __asg_profiles
    # Extract profiles from AWS credentials and config files
    set -l profiles (cat ~/.aws/credentials ~/.aws/config 2>/dev/null | grep '^\[' | tr -d '[]' | sed 's/profile //' | sort -u)

    # If fzf is installed, use it for interactive selection
    if type -q fzf
        printf "%s\n" $profiles | fzf --height 40% --reverse --header="Select AWS Profile"
    else
        # Fallback to standard completion
        printf "%s\n" $profiles
    end
end

# Register completions
complete -c asg -s p -l profile -d "Specify AWS profile" -xa "(__asg_profiles)"
complete -c asg -s v -l verbose -d "Show additional account information"
complete -c asg -s h -l help -d "Show help message"

function git_root
    # Start from the current directory
    set -l current_dir (pwd)
    
    # Keep going up until we find .git or reach root
    while test "$current_dir" != "/"
        if test -d "$current_dir/.git"
            echo $current_dir
            return 0
        end
        set current_dir (dirname $current_dir)
    end
    
    # If we reach here, no .git directory was found
    echo "Not a git repository (or any of the parent directories)" >&2
    return 1
end 
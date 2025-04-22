# Global variables
set -g __sf_last_dir $PWD
set -g __sf_debug 0
set -g __sf_processing_hooks 0
set -g __sf_active_smartfish "" # Stores active .smartfish files as "path|dir" pairs
set -g __sf_initialized 0

function __sf_debug
    if test $__sf_debug -eq 1
        echo "SMARTFISH: $argv" >&2
    end
end

function __sf_find_all_roots --argument dir
    # Find all .smartfish files from the given directory up to root
    set -l norm_dir (string replace -r '^/+' '/' $dir)
    set -l norm_dir (string replace -r '/+$' '' $norm_dir)
    if test -z "$norm_dir"
        set norm_dir "/"
    end
    
    set -l current_dir $norm_dir
    set -l roots
    while [ "$current_dir" != "/" ]
        set -l hookfile "$current_dir/.smartfish"
        if test -e $hookfile
            set -a roots "$hookfile|$current_dir"
        end
        set current_dir (realpath $current_dir/..)
    end
    
    if test -e "/.smartfish"
        set -a roots "/.smartfish|/"
    end
    
    if test -n "$roots"
        for root in $roots
            echo $root
        end
    else
        __sf_debug "No .smartfish files found for $norm_dir"
    end
end

function __sf_get_hooks --argument hookfile hook_type
    if test -z "$hookfile" -o ! -e "$hookfile"
        __sf_debug "No hooks found for $hookfile (file does not exist)"
        echo "[]"
        return
    end
    
    set -l hooks_json (jq -r --arg type "$hook_type" '.[$type] // []' $hookfile 2>/dev/null)
    if test -z "$hooks_json" -o "$hooks_json" = "null"
        echo "[]"
    else
        echo $hooks_json
    end
end

function __sf_update_root --argument dir hook_type action hook_content
    set -l hookfile "$dir/.smartfish"
    if not test -e $hookfile
        echo '{"enter":[],"exit":[]}' > $hookfile
        chmod 600 $hookfile
        __sf_debug "Created new .smartfish root at $hookfile"
    end
    
    set -l temp_file (mktemp)
    
    if test "$action" = "add"
        set -l hook_exists (jq -r --arg type "$hook_type" --arg hook "$hook_content" '.[$type][] | select(. == $hook)' $hookfile 2>/dev/null)
        if test -n "$hook_exists"
            __sf_debug "Hook '$hook_content' already exists in $hookfile for $hook_type, skipping"
            rm $temp_file
            return
        end
        jq --arg type "$hook_type" --arg hook "$hook_content" '
            .[$type] += [$hook]
        ' $hookfile > $temp_file 2>/dev/null
    else if test "$action" = "remove"
        if test -z "$hook_content"
            jq --arg type "$hook_type" '
                .[$type] = []
            ' $hookfile > $temp_file 2>/dev/null
        else
            jq --arg type "$hook_type" --arg hook "$hook_content" '
                .[$type] = [.[$type][] | select(. != $hook)]
            ' $hookfile > $temp_file 2>/dev/null
        end
    else if test "$action" = "remove_env"
        set -l env_name $hook_content
        set -l enter_hook "set -gx $env_name"
        set -l exit_hook "set -e $env_name"
        jq --arg enter_pattern "$enter_hook" --arg exit_pattern "$exit_hook" '
            .enter = [.enter[] | select(. | startswith($enter_pattern) | not)] |
            .exit = [.exit[] | select(. | startswith($exit_pattern) | not)]
        ' $hookfile > $temp_file 2>/dev/null
    end
    
    if test -s $temp_file
        mv $temp_file $hookfile
        __sf_debug "Updated .smartfish root at $hookfile"
    else
        rm $temp_file
        __sf_debug "Failed to update .smartfish root for $action in $dir"
    end
end

function __sf_process_hooks --argument hook_type hookfile dir
    if test $__sf_processing_hooks -eq 1
        __sf_debug "Already processing hooks, skipping recursive call for $hook_type hooks"
        return
    end
    
    set -g __sf_processing_hooks 1
    __sf_debug "Processing $hook_type hooks for $dir from $hookfile"
    
    if test -z "$hookfile" -o ! -e "$hookfile"
        __sf_debug "No $hook_type hooks found for $dir (no .smartfish file)"
        set -g __sf_processing_hooks 0
        return
    end
    
    set -l hooks_json (__sf_get_hooks $hookfile $hook_type)
    if test "$hooks_json" = "[]"
        __sf_debug "No $hook_type hooks defined in $hookfile for $dir"
        set -g __sf_processing_hooks 0
        return
    end
    
    __sf_debug "Executing $hook_type hooks from $hookfile for $dir"
    
    # Execute hooks in the context of the specified directory
    for cmd in (echo $hooks_json | jq -r '.[]' 2>/dev/null)
        set -l cmd_first_word (string split -m 1 " " -- $cmd | head -n 1)
        if test -z "$cmd_first_word"
            __sf_debug "Skipping empty hook from $hookfile"
            continue
        end
        if not command -q $cmd_first_word
            __sf_debug "Skipping invalid hook from $hookfile: $cmd (command '$cmd_first_word' not found)"
            continue
        end
        
        __sf_debug "Running: $cmd in context of $dir"
        pushd $dir >/dev/null
        eval $cmd 2>/dev/null
        popd >/dev/null
    end
    
    set -g __sf_processing_hooks 0
end

function __sf_update_active_smartfish --argument old_dir new_dir
    # Get all .smartfish files for old and new directories
    set -l old_roots (__sf_find_all_roots $old_dir)
    set -l new_roots (__sf_find_all_roots $new_dir)
    
    __sf_debug "Old roots: $old_roots"
    __sf_debug "New roots: $new_roots"
    
    # Convert roots to arrays for comparison
    set -l old_root_list
    set -l new_root_list
    for root in $old_roots
        set -a old_root_list $root
    end
    for root in $new_roots
        set -a new_root_list $root
    end
    
    # Find roots that are no longer active (in old but not in new)
    set -l exiting_roots
    for old_root in $old_root_list
        set -l found 0
        for new_root in $new_root_list
            if test "$old_root" = "$new_root"
                set found 1
                break
            end
        end
        if test $found -eq 0
            set -a exiting_roots $old_root
        end
    end
    
    # Find roots that are newly active (in new but not in old)
    set -l entering_roots
    for new_root in $new_root_list
        set -l found 0
        for old_root in $old_root_list
            if test "$new_root" = "$old_root"
                set found 1
                break
            end
        end
        if test $found -eq 0
            set -a entering_roots $new_root
        end
    end
    
    # Run exit hooks for roots that are no longer active
    for root in $exiting_roots
        set -l root_file (string split "|" $root)[1]
        set -l root_dir (string split "|" $root)[2]
        __sf_debug "Leaving scope of $root_file in $root_dir"
        __sf_process_hooks "exit" $root_file $root_dir
    end
    
    # Run enter hooks for newly active roots
    for root in $entering_roots
        set -l root_file (string split "|" $root)[1]
        set -l root_dir (string split "|" $root)[2]
        # Check if already active to avoid re-running
        set -l is_active 0
        for active_root in $__sf_active_smartfish
            if test "$active_root" = "$root"
                set is_active 1
                break
            end
        end
        if test $is_active -eq 0
            __sf_debug "Entering scope of $root_file in $root_dir"
            __sf_process_hooks "enter" $root_file $root_dir
        end
    end
    
    # Update active smartfish list
    set -g __sf_active_smartfish $new_root_list
    __sf_debug "Updated active smartfish: $__sf_active_smartfish"
end

function __sf_on_pwd_change --on-variable PWD
    if not set -q __sf_last_dir
        set -g __sf_last_dir $PWD
        return
    end
    
    if test "$PWD" = "$__sf_last_dir"
        __sf_debug "PWD didn't actually change, skipping hooks"
        return
    end
    
    __sf_debug "Directory change detected: $__sf_last_dir -> $PWD"
    
    # Update active .smartfish files and run hooks
    __sf_update_active_smartfish $__sf_last_dir $PWD
    
    # Update last dir
    set -g __sf_last_dir $PWD
end

function smartfish --description "Directory-aware hooks for Fish shell"
    set -l cmd
    switch $argv[1]
        case h
            set cmd help
        case a
            set cmd active
        case d
            set cmd debug
        case e
            set cmd enter
        case x
            set cmd exit
        case s
            set cmd setenv
        case r
            set cmd remove
        case l
            set cmd list
        case c
            set cmd clean
        case sync
            set cmd sync
        case '*'
            set cmd $argv[1]
    end

    if not set -q argv[1]
        __sf_usage
        return 0
    end

    switch $cmd
        case help
            __sf_usage
       case active
          if test -z "$__sf_active_smartfish"
              echo "No active .smartfish files"
          else
              echo "Active .smartfish files:"
              for entry in $__sf_active_smartfish
                  set -l root_file (string split "|" $entry)[1]
                  set -l root_dir (string split "|" $entry)[2]
                  echo "  $root_file (in $root_dir)"
              end
          end
        case debug
            if test $__sf_debug -eq 0
                set -g __sf_debug 1
                echo "Debug mode enabled"
            else
                set -g __sf_debug 0
                echo "Debug mode disabled"
            end
        case enter
            if not set -q argv[2]
                echo "Error: Missing command for enter hook"
                echo "Usage: smartfish enter 'COMMAND'"
                return 1
            end
            set -l cmd (string join " " $argv[2..-1])
            __sf_update_root $PWD "enter" "add" $cmd
            echo "Added enter hook: $cmd"
        case exit
            if not set -q argv[2]
                echo "Error: Missing command for exit hook"
                echo "Usage: smartfish exit 'COMMAND'"
                return 1
            end
            set -l cmd (string join " " $argv[2..-1])
            __sf_update_root $PWD "exit" "add" $cmd
            echo "Added exit hook: $cmd"
        case setenv
            if not set -q argv[2]; or not set -q argv[3]
                echo "Error: Missing name or value for environment variable"
                echo "Usage: smartfish setenv NAME VALUE"
                return 1
            end
            set -l env_name $argv[2]
            set -l env_value $argv[3]
            switch $env_value
                case '@DIR'
                    set env_value '$PWD'
                case '@PARENT'
                    set env_value '$PWD/..'
            end
            __sf_update_root $PWD "enter" "add" "set -gx $env_name $env_value"
            __sf_update_root $PWD "exit" "add" "set -e $env_name 2>/dev/null"
            echo "Added environment variable: $env_name=$env_value"
            set -gx $env_name (eval echo $env_value)
            echo "Set $env_name = $env_value"
        case remove
            if not set -q argv[2]
                echo "Error: Missing hook type or variable name"
                echo "Usage: smartfish remove [enter|exit|env] NAME"
                return 1
            end
            set -l hook_type $argv[2]
            set -l hook_name
            if set -q argv[3]
                set hook_name $argv[3]
            end
            if test "$hook_type" = "env"
                if test -z "$hook_name"
                    echo "Error: Missing environment variable name"
                    return 1
                end
                if set -q $hook_name
                    set -e $hook_name
                    echo "Unset environment variable: $hook_name"
                end
                __sf_update_root $PWD "remove_env" $hook_name
                echo "Removed environment variable hooks for: $hook_name"
            else
                if test "$hook_type" != "enter" -a "$hook_type" != "exit"
                    echo "Error: Hook type must be 'enter', 'exit', or 'env'"
                    return 1
                end
                __sf_update_root $PWD $hook_type "remove" $hook_name
                if test -z "$hook_name"
                    echo "Removed all $hook_type hooks"
                else
                    echo "Removed $hook_type hook containing: $hook_name"
                end
            end
        case list
            set -l current_dir $PWD
            echo "SmartFish hooks in current directory tree:"
            echo "----------------------------------------"
            set -l found_hooks 0
            while [ "$current_dir" != "/" ]
                set -l hookfile "$current_dir/.smartfish"
                if test -e $hookfile
                    set -l enter_hooks (jq -r '.enter // [] | length' $hookfile 2>/dev/null)
                    set -l exit_hooks (jq -r '.exit // [] | length' $hookfile 2>/dev/null)
                    if test "$enter_hooks" -gt 0 -o "$exit_hooks" -gt 0
                        echo "Hooks in $current_dir (root: $hookfile):"
                        if test "$enter_hooks" -gt 0
                            echo "  Enter hooks:"
                            jq -r '.enter[] | "    " + .' $hookfile 2>/dev/null
                        end
                        if test "$exit_hooks" -gt 0
                            echo "  Exit hooks:"
                            jq -r '.exit[] | "    " + .' $hookfile 2>/dev/null
                        end
                        echo ""
                        set found_hooks 1
                    end
                end
                set current_dir (realpath $current_dir/..)
            end
            if test $found_hooks -eq 0
                echo "No hooks found in current directory tree"
            end
        case edit
            set -l hookfile ".smartfish"
            if not test -e $hookfile
                echo '{"enter":[],"exit":[]}' > $hookfile
                chmod 600 $hookfile
                __sf_debug "Created new .smartfish root at $hookfile"
            end
            set -l editor $EDITOR
            if test -z "$editor"
                set editor vi
            end
            $editor $hookfile
        case reset
            echo "Resetting active smartfish hooks"
            __sf_scan_tree
            set -g __sf_active_smartfish ""
            set -l roots (__sf_find_all_roots $PWD)
            set -g __sf_active_smartfish $roots
            for root in $roots
                set -l root_file (string split "|" $root)[1]
                set -l root_dir (string split "|" $root)[2]
                __sf_process_hooks "enter" $root_file $root_dir
            end
            echo "Reset active smartfish hooks"
        case sync
            __sf_scan_tree
        case clean
            echo "No cache to clean"
        case "*"
            echo "Error: Unknown command: $argv[1]"
            __sf_usage
            return 1
    end
end

function __sf_scan_tree
    __sf_debug "Scanning directory tree from $PWD to root for .smartfish files"
    set -l current_dir $PWD
    set -l found_files
    while [ "$current_dir" != "/" ]
        set -l hookfile "$current_dir/.smartfish"
        if test -e $hookfile
            if jq empty $hookfile 2>/dev/null
                set -a found_files $hookfile
            else
                __sf_debug "Error: $hookfile is not in JSON format, skipping"
            end
        end
        set current_dir (realpath $current_dir/..)
    end
    if test -e "/.smartfish"
        if jq empty "/.smartfish" 2>/dev/null
            set -a found_files "/.smartfish"
        end
    end
    if test -n "$found_files"
        echo "Found .smartfish files:"
        for file in $found_files
            echo "  $file"
        end
    else
        echo "No .smartfish files found in directory tree"
    end
end

function __sf_usage
    echo "SmartFish - Directory-aware hooks for Fish shell"
    echo ""
    echo "Usage: smartfish COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  active, a               List active .smartfish files"
    echo "  reset                   Reset active .smartfish files"
    echo "  enter, e COMMAND        Add command to run when entering directory"
    echo "  exit, x COMMAND         Add command to run when exiting directory"
    echo "  setenv, s NAME VALUE    Set environment variable in directory"
    echo "  remove, r TYPE [NAME]   Remove hook or environment variable"
    echo "  list, l                 List all hooks in current directory tree"
    echo "  edit                    Edit local .smartfish file"
    echo "  sync                    List .smartfish files from CWD to root"
    echo "  clean                   No-op (no cache to clean)"
    echo "  debug, d                Toggle debug mode"
    echo "  help, h                 Show this help message"
    echo ""
    echo "Special values for environment variables:"
    echo "  @DIR                    Current directory path"
    echo "  @PARENT                 Parent directory path"
    echo ""
    echo "Examples:"
    echo "  smartfish enter 'echo \"Entering project directory\"'"
    echo "  smartfish exit 'echo \"Leaving project directory\"'"
    echo "  smartfish setenv PROJECT_ROOT @DIR"
    echo "  smartfish setenv API_KEY secret123"
    echo "  smartfish remove env API_KEY"
    echo "  smartfish sync"
    echo "  smartfish list"
end

# Initial run for the starting directory
if not set -q __sf_initialized
    set -g __sf_initialized 1
    set -l roots (__sf_find_all_roots $PWD)
    set -g __sf_active_smartfish $roots
    for root in $roots
        set -l root_file (string split "|" $root)[1]
        set -l root_dir (string split "|" $root)[2]
        __sf_debug "Initializing enter hooks for $root_file in $root_dir"
        __sf_process_hooks "enter" $root_file $root_dir
    end
end

# Completions for smartfish
complete -f -c smartfish -n "__fish_use_subcommand" -a "enter\t'Add enter hook' exit\t'Add exit hook' setenv\t'Set environment variable' remove\t'Remove hook' list\t'List hooks' edit\t'Edit hooks file' sync\t'List .smartfish files' clean\t'No-op (no cache)' debug\t'Toggle debug mode' help\t'Show help'"
complete -f -c smartfish -n "__fish_use_subcommand" -a "a\t'List active .smartfish files' e\t'Add enter hook' x\t'Add exit hook' s\t'Set environment variable' r\t'Remove hook' l\t'List hooks' c\t'No-op (no cache)' d\t'Toggle debug mode' h\t'Show help'"
complete -f -c smartfish -n "__fish_seen_subcommand_from remove r" -a "enter\t'Enter hooks' exit\t'Exit hooks' env\t'Environment variables'"
complete -f -c smartfish -n "__fish_seen_subcommand_from clean c" -a "--rescan\t'Rescan directory tree'"
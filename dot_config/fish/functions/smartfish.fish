# Global variables
set -g __sf_last_dir $PWD
set -g __sf_debug 0
set -g __sf_processing_hooks 0
set -g __sf_active_smartfish "" # Stores active .smartfish files as "path|dir" pairs
set -g __sf_initialized 0
set -g __sf_format_version 2 # Bump version due to breaking change

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

function __sf_ensure_file_structure --argument hookfile
    if not test -e $hookfile
        # Create new file with all sections
        echo '{\n  "enter": [],\n  "exit": [],\n  "env": {}\n}' > $hookfile
        chmod 600 $hookfile
        __sf_debug "Created new .smartfish root at $hookfile (v$__sf_format_version format)"
        return 0
    end

    # Check and potentially migrate older structures (simple check for now)
    if not jq -e '.env' $hookfile > /dev/null 2>&1
        # Add env key if missing (basic migration)
        set -l temp_file (mktemp)
        jq '.env = {}' $hookfile > $temp_file 2>/dev/null
        if test -s $temp_file
            mv $temp_file $hookfile
            __sf_debug "Added missing 'env' key to $hookfile"
        else
            rm $temp_file
            __sf_debug "Failed to add 'env' key to $hookfile"
            return 1 # Indicate failure
        end
    end

    # Ensure basic keys exist (could add more checks)
    if not jq -e '.enter' $hookfile > /dev/null 2>&1; or not jq -e '.exit' $hookfile > /dev/null 2>&1
       __sf_debug "Warning: $hookfile might be missing enter/exit keys."
    end

    return 0
end

function __sf_get_hooks --argument hookfile hook_type
    if test -z "$hookfile" -o ! -e "$hookfile"
        __sf_debug "No hooks found for $hookfile (file does not exist)"
        echo "[]"
        return
    end
    
    if test "$hook_type" = "env"
        # Return env map as JSON object
        set hooks_json (jq -r '.env // {}' $hookfile 2>/dev/null)
        if test -z "$hooks_json" -o "$hooks_json" = "null"
            echo "{}"
        else
            echo $hooks_json
        end
    else
        # Return enter/exit commands as JSON array
        set hooks_json (jq -r --arg type "$hook_type" '.[$type] // []' $hookfile 2>/dev/null)
        if test -z "$hooks_json" -o "$hooks_json" = "null"
            echo "[]"
        else
            echo $hooks_json
        end
    end
end

function __sf_update_root --argument dir hook_type action
    set -l hookfile "$dir/.smartfish"
    __sf_ensure_file_structure $hookfile
    if test $status -ne 0
        echo "Error: Could not ensure file structure for $hookfile" >&2
        return 1
    end
    
    set -l temp_file (mktemp)
    set -l jq_filter_string # The jq filter program as a string
    
    switch $hook_type
        case env
            argparse --name="__sf_update_root env" key= value= -- $argv[4..-1]
            if test $status -ne 0; or not set -q _flag_key
                 echo "Error: __sf_update_root env requires --key" >&2; rm $temp_file; return 1
            end
            set -l key $_flag_key

            switch $action
                case add # Add or update env var
                    if not set -q _flag_value
                        echo "Error: __sf_update_root env add requires --value" >&2; rm $temp_file; return 1
                    end
                    set -l value $_flag_value
                    # Use JSON.stringify equivalent in jq to properly escape the string
                    set jq_filter_string ".env[\$key] = \$value"
                case remove # Remove env var
                    # Use $key parameter instead of direct string interpolation
                    set jq_filter_string "del(.env[\$key])"
                case '*'
                    echo "Error: Unknown action '$action' for hook type 'env'" >&2; rm $temp_file; return 1
            end

            # Apply the jq filter with --arg for proper argument handling
            if jq --arg key "$key" --arg value "$_flag_value" "$jq_filter_string" "$hookfile" > "$temp_file" 2>/dev/null
                # Continue with validation and file move
                if jq -e . "$temp_file" > /dev/null 2>&1
                    mv "$temp_file" "$hookfile"
                    __sf_debug "Updated .smartfish root at $hookfile (action: $action, type: $hook_type)"
                else
                    rm "$temp_file"
                    __sf_debug "Error: jq filter produced invalid JSON. Filter: $jq_filter_string" >&2
                    return 1
                end
            else
                set -l jq_status $status
                rm "$temp_file"
                __sf_debug "Error: Failed to apply jq update (status $jq_status). Filter: $jq_filter_string" >&2
                return 1
            end

        case enter exit
            if not set -q argv[4]
                echo "Error: __sf_update_root $hook_type requires hook_content" >&2; rm $temp_file; return 1
            end
            set -l hook_content $argv[4]

            switch $action
                case add
                    # Check if hook already exists using --arg for safe parameter passing
                    if jq -e --arg type "$hook_type" --arg hook "$hook_content" '.[$type][] | select(. == $hook)' $hookfile > /dev/null 2>&1
                        __sf_debug "Hook '$hook_content' already exists in $hookfile for $hook_type, skipping"
                        rm $temp_file
                        return 0 # Not an error
                    end
                    # Use $hook parameter instead of string interpolation/escaping
                    set jq_filter_string '.[$type] += [$hook]'
                case remove
                    if test -z "$hook_content" # Should not happen with current CLI
                        echo "Error: Empty hook content provided for removal." >&2; rm $temp_file; return 1
                    end
                    # Use $hook parameter instead of string interpolation/escaping
                    set jq_filter_string '.[$type] = [.[$type][] | select(. != $hook)]'
                case '*'
                    echo "Error: Unknown action '$action' for hook type '$hook_type'" >&2; rm $temp_file; return 1
            end

            # Apply the jq filter with --arg for proper argument handling
            if jq --arg type "$hook_type" --arg hook "$hook_content" "$jq_filter_string" "$hookfile" > "$temp_file" 2>/dev/null
                # Check if output is valid JSON before moving
                if jq -e . "$temp_file" > /dev/null 2>&1
                    mv "$temp_file" "$hookfile"
                    __sf_debug "Updated .smartfish root at $hookfile (action: $action, type: $hook_type)"
                else
                    rm "$temp_file"
                    __sf_debug "Error: jq filter produced invalid JSON. Filter: $jq_filter_string" >&2
                    return 1
                end
            else
                # jq command failed
                set -l jq_status $status
                rm "$temp_file"
                __sf_debug "Error: Failed to apply jq update (status $jq_status). Filter: $jq_filter_string" >&2
                return 1
            end
        case '*'
            echo "Error: Unknown hook_type '$hook_type'" >&2; rm $temp_file; return 1
    end
    return 0
end

function __sf_process_hooks --argument hook_type hookfile dir
    if test $__sf_processing_hooks -eq 1
        __sf_debug "Already processing hooks, skipping recursive call for $hook_type hooks"
        return
    end
    
    set -g __sf_processing_hooks 1
    __sf_debug "Processing $hook_type hooks for $dir from $hookfile"
    
    if test -z "$hookfile" -o ! -e "$hookfile"
        __sf_debug "No $hook_type processing for $dir (.smartfish file not found)"
        set -g __sf_processing_hooks 0
        return
    end
    
    __sf_debug "Processing $hook_type actions for $dir from $hookfile"
    
    # Process Env Vars first (on enter/exit)
    if test "$hook_type" = "enter" -o "$hook_type" = "exit"
        set -l env_vars_json (__sf_get_hooks $hookfile env)
        if test "$env_vars_json" != "{}"
            __sf_debug "Processing env vars ($hook_type) from $hookfile for $dir"
            for kv in (echo $env_vars_json | jq -r '. | to_entries[] | "\(.key)\t\(.value)"' 2>/dev/null)
                set -l key (string split "\t" -- $kv)[1]
                set -l value (string split -m1 "\t" -- $kv)[2]
                if test -z "$key"; continue; end # Skip if key is somehow empty

                if test "$hook_type" = "enter"
                    # Evaluate value in case it contains $PWD or other vars/commands
                    # Handle @DIR and @PARENT specifically before eval
                    set -l final_value $value
                    switch $value
                        case '@DIR'
                            set final_value "$dir" # Use the hook's directory
                        case '@PARENT'
                            set final_value (realpath "$dir/..")
                    end
                    set -l evaluated_value (eval echo "$final_value")
                    __sf_debug "Setting env var: $key = '$evaluated_value' (original: '$value')"
                    set -gx "$key" "$evaluated_value"
                else # exit
                    __sf_debug "Unsetting env var: $key"
                    set -e "$key"
                end
            end
        end
    end

    # Process Command Hooks (enter/exit)
    if test "$hook_type" = "enter" -o "$hook_type" = "exit"
        set -l hooks_json (__sf_get_hooks $hookfile $hook_type)
        if test "$hooks_json" = "[]"
            __sf_debug "No $hook_type command hooks defined in $hookfile for $dir"
        else
            __sf_debug "Executing $hook_type command hooks from $hookfile for $dir"
            # Execute hooks in the context of the specified directory
            pushd $dir >/dev/null
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
                eval $cmd 2>/dev/null
            end
            popd >/dev/null
        end
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

# Updated function to get specific hooks for completion, properly quoted
function __sf_get_hooks_for_completion --argument hookfile hook_type
    if test -e "$hookfile"; and contains "$hook_type" enter exit
        # 1. Extract hooks as JSON strings
        # 2. Pipe each JSON string to jq -r . to get the raw string
        # 3. Pipe the raw string to printf %q to quote it for fish completions
        jq -r --arg type "$hook_type" '..[$type][]? // empty | @json' "$hookfile" 2>/dev/null | while read -l hook_json
            set -l raw_hook (echo $hook_json | jq -r .)
            printf "%q\n" "$raw_hook"
        end
    end
end

# Updated function to get environment variables for completion, properly quoted
function __sf_get_env_for_completion --argument hookfile
    if test -e "$hookfile"
        # 1. Extract keys as JSON strings
        # 2. Pipe each JSON string to jq -r . to get the raw key
        # 3. Pipe the raw key to printf %q to quote it for fish completions
        jq -r '.env // {} | keys[] | @json' "$hookfile" 2>/dev/null | while read -l key_json
            set -l raw_key (echo $key_json | jq -r .)
            printf "%q\n" "$raw_key"
        end
    end
end

# New function to get .smartfish files in current directory tree
function __sf_get_smartfish_files
    set -l current_dir $PWD
    set -l files
    while [ "$current_dir" != "/" ]
        set -l hookfile "$current_dir/.smartfish"
        if test -e "$hookfile"
            set -a files "$hookfile"
        end
        set current_dir (realpath "$current_dir/..")
    end
    if test -e "/.smartfish"
        set -a files "/.smartfish"
    end
    for file in $files
        echo "$file"
    end
end

# Updated function to format hooks as a table with dynamic alignment
function __sf_list_hooks_as_table
    set -l current_dir $PWD
    set -l found_hooks 0
    set -l hooks_table
    set -l max_location_len 8 # Minimum for "Location"
    set -l max_command_len 7 # Minimum for "Command" / "Variable = Value"

    # Collect hooks and calculate max lengths
    while [ "$current_dir" != "/" ]
        set -l hookfile "$current_dir/.smartfish"
        if test -e "$hookfile"
            # Process enter/exit commands
            for type in enter exit
                set -l commands (jq -r --arg t "$type" '.[$t][]? // empty' "$hookfile" 2>/dev/null)
                if test -n "$commands"
                    set found_hooks 1
                    for cmd in $commands
                        set -a hooks_table "$current_dir|$type|$cmd"
                        set -l loc_len (string length "$current_dir")
                        set -l cmd_len (string length "$cmd")
                        if test $loc_len -gt $max_location_len; set max_location_len $loc_len; end
                        if test $cmd_len -gt $max_command_len; set max_command_len $cmd_len; end
                    end
                end
            end
            # Process env vars
            set -l env_vars (jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$hookfile" 2>/dev/null)
             if test -n "$env_vars"
                set found_hooks 1
                for var in $env_vars
                    set -a hooks_table "$current_dir|env|$var"
                    set -l loc_len (string length "$current_dir")
                    set -l cmd_len (string length "$var")
                    if test $loc_len -gt $max_location_len; set max_location_len $loc_len; end
                    if test $cmd_len -gt $max_command_len; set max_command_len $cmd_len; end
                end
            end
        end
        set current_dir (realpath $current_dir/..)
    end

    # Check root file
    if test -e "/.smartfish"
        set hookfile "/.smartfish"
         # Process enter/exit commands
        for type in enter exit
            set -l commands (jq -r --arg t "$type" '.[$t][]? // empty' "$hookfile" 2>/dev/null)
            if test -n "$commands"
                set found_hooks 1
                for cmd in $commands
                    set -a hooks_table "/|$type|$cmd"
                    set -l cmd_len (string length "$cmd")
                    if test $cmd_len -gt $max_command_len; set max_command_len $cmd_len; end
                end
            end
        end
        # Process env vars
        set -l env_vars (jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$hookfile" 2>/dev/null)
         if test -n "$env_vars"
            set found_hooks 1
            for var in $env_vars
                set -a hooks_table "/|env|$var"
                set -l cmd_len (string length "$var")
                if test $cmd_len -gt $max_command_len; set max_command_len $cmd_len; end
            end
        end
    end

    echo "SmartFish hooks in current directory tree:"
    echo "----------------------------------------"
    # Adjust header based on max length
    set -l header_format "%-*s | %s | %s\n"
    set -l separator_format "%s-|-%s-|-%s\n"
    printf $header_format $max_location_len "Location" "Type" "Command / Variable = Value"
    printf $separator_format (string repeat -n $max_location_len "-") "----" (string repeat -n $max_command_len "-")

    if test $found_hooks -eq 0
        echo "No hooks found in directory tree"
    else
        for hook_entry in $hooks_table
            set -l location (string split "|" $hook_entry)[1]
            set -l type (string split "|" $hook_entry)[2]
            set -l command (string split -m1 "|" $hook_entry)[3]
            printf "%-*s | %-4s | %s\n" $max_location_len "$location" "$type" "$command"
        end
    end
end

function __sf_color --argument color text
    switch $color
        case red
            echo -e "\033[31m$text\033[0m"
        case green
            echo -e "\033[32m$text\033[0m"
        case yellow
            echo -e "\033[33m$text\033[0m"
        case blue
            echo -e "\033[34m$text\033[0m"
        case '*'
            echo "$text"
    end
end

function __sf_get_all_hooks_formatted --argument hookfile
    set -l hooks_list # Use a list to build output
    if test -e "$hookfile"
        # Get enter/exit hooks
        for type in enter exit
            set -l commands (jq -r --arg t "$type" '.[$t][]? // empty | @json' "$hookfile" 2>/dev/null)
            for cmd_json in $commands
                set -l cmd (echo $cmd_json | jq -r .)
                 set -a hooks_list "'$type $cmd'"
            end
        end
        # Get env vars
        set -l env_keys (jq -r '.env // {} | keys[] | @json' "$hookfile" 2>/dev/null)
        for key_json in $env_keys
             set -l key (echo $key_json | jq -r .)
            set -a hooks_list "'(env) $key'"
        end
    end
    if test -n "$hooks_list"
        # Print each element on a new line
        printf "%s\n" $hooks_list
    end
end

# Updated smartfish function
function smartfish --description "Directory-aware hooks for Fish shell (v$__sf_format_version)"
    set -l cmd $argv[1]

    if not set -q argv[1]
        __sf_usage
        return 0
    end

    switch $cmd
        case help
            __sf_usage
        case active
            if not set -q argv[2]
                echo "Error: Missing active subcommand"
                echo "Usage: smartfish active [list|activate] ..."
                return 1
            end
            set -l subcmd $argv[2]
            switch $subcmd
                case list
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
                case activate
                    if set -q argv[3]
                        if test "$argv[3]" = "--all"
                            echo "Activating all .smartfish files in directory tree"
                            set -g __sf_active_smartfish ""
                            set -l roots (__sf_find_all_roots $PWD)
                            set -g __sf_active_smartfish $roots
                            for root in $roots
                                set -l root_file (string split "|" $root)[1]
                                set -l root_dir (string split "|" $root)[2]
                                __sf_process_hooks "enter" $root_file $root_dir
                            end
                            echo "Activated all .smartfish files"
                        else
                            set -l hookfile "$argv[3]"
                            if not test -e "$hookfile"
                                echo "Error: .smartfish file '$hookfile' does not exist"
                                return 1
                            end
                            set -l root_dir (dirname $hookfile)
                            set -l already_active 0
                            for active_root in $__sf_active_smartfish
                                set -l active_file (string split "|" $active_root)[1]
                                if test "$active_file" = "$hookfile"
                                    set already_active 1
                                    break
                                end
                            end
                            if test $already_active -eq 0
                                set -a __sf_active_smartfish "$hookfile|$root_dir"
                                __sf_process_hooks "enter" $hookfile $root_dir
                                echo "Activated $hookfile"
                            else
                                echo "$hookfile is already active"
                            end
                        end
                    else
                        echo "Error: Missing file path or --all option"
                        echo "Usage: smartfish active activate [PATH|--all]"
                        return 1
                    end
                case "*"
                    echo "Error: Invalid active subcommand: $subcmd"
                    echo "Usage: smartfish active [list|activate] ..."
                    return 1
            end
        case debug
            if test $__sf_debug -eq 0
                set -g __sf_debug 1
                echo "Debug mode enabled"
            else
                set -g __sf_debug 0
                echo "Debug mode disabled"
            end
        case hook
            if not set -q argv[2]
                echo "Error: Missing hook subcommand"
                echo "Usage: smartfish hook [create|delete|update|list] ..."
                return 1
            end
            set -l subcmd $argv[2]
            switch $subcmd
                case create
                    # Use a single argparse call to handle all potential flags
                    argparse --name="smartfish hook create" --min-args=0 'type=' 'command=' 'key=' 'value=' -- $argv[3..-1]
                    if test $status -ne 0
                        # Argparse likely printed a specific error
                        echo "Usage: smartfish hook create --type TYPE [options]" >&2
                        return 1
                    end

                    # Validate --type
                    if not set -q _flag_type; or not contains "$_flag_type" enter exit env
                        echo "Error: --type is required and must be 'enter', 'exit', or 'env'." >&2
                        echo "Usage: smartfish hook create --type [enter|exit|env] ..." >&2
                        return 1
                    end
                    set -l hook_type $_flag_type

                    # Validate based on type
                    if test "$hook_type" = "env"
                        # Check required flags for env
                        if not set -q _flag_key; or not set -q _flag_value
                            echo "Error: For --type env, both --key NAME and --value VALUE are required." >&2
                            echo "Usage: smartfish hook create --type env --key NAME --value VALUE" >&2
                            return 1
                        end
                        # Check for disallowed flags for env
                        if set -q _flag_command
                            echo "Error: --command cannot be used with --type env." >&2
                            return 1
                        end

                        set -l env_name $_flag_key
                        set -l env_value $_flag_value
                        set -l value_to_store $env_value

                        # Let __sf_update_root handle proper escaping with jq --arg
                        if __sf_update_root $PWD "env" "add" --key "$env_name" --value "$value_to_store"
                            echo "Created environment variable hook: $env_name=$env_value"
                            set -l final_value $env_value
                            switch $env_value
                                case '@DIR'
                                    set final_value $PWD
                                case '@PARENT'
                                    set final_value (realpath "$PWD/..")
                            end
                            set -gx "$env_name" (eval echo "$final_value")
                            echo "Set $env_name = '$final_value' (in current session)" # Added quotes for clarity
                        else
                             echo "Error: Failed to create environment variable hook $env_name" >&2
                             return 1
                        end

                    else # enter or exit
                        # Check required flags for enter/exit
                        if not set -q _flag_command
                            echo "Error: For --type $hook_type, --command COMMAND is required." >&2
                            echo "Usage: smartfish hook create --type $hook_type --command \"COMMAND\"" >&2
                            return 1
                        end
                        # Check for disallowed flags for enter/exit
                        if set -q _flag_key; or set -q _flag_value
                            echo "Error: --key and --value cannot be used with --type $hook_type." >&2
                            return 1
                        end
                        set -l cmd $_flag_command

                        # Pass the command directly without escaping - __sf_update_root will handle it
                        if __sf_update_root $PWD $hook_type "add" "$cmd"
                             echo "Created $hook_type hook: '$cmd'" # Added quotes for clarity
                        else
                             echo "Error: Failed to create $hook_type hook" >&2
                             return 1
                        end
                    end
                case delete
                    # Use argparse to parse arguments
                    argparse --name="smartfish hook delete" --min-args=0 'type=' 'command=' 'key=' -- $argv[3..-1]
                    if test $status -ne 0
                        return 1
                    end

                    # Validate hook type
                    if not set -q _flag_type; or test -z "$_flag_type"
                        echo "Error: --type is required. Must be 'enter', 'exit', or 'env'."
                        echo "Usage: smartfish hook delete --type enter|exit --command COMMAND"
                        echo "       smartfish hook delete --type env --key KEY"
                        return 1
                    end
                    if not contains $_flag_type enter exit env
                        echo "Error: Invalid --type. Must be 'enter', 'exit', or 'env'."
                        return 1
                    end
                    set -l hook_type $_flag_type
                    set -l hookfile "$PWD/.smartfish"

                    if test "$hook_type" = "env"
                        # Validate env key
                        if not set -q _flag_key; or test -z "$_flag_key"
                            echo "Error: --key is required for deleting env hooks." >&2
                            echo "Usage: smartfish hook delete --type env --key KEY" >&2
                            return 1
                        end
                         if set -q _flag_command
                            echo "Error: --command cannot be used with --type env for deletion." >&2
                            return 1
                        end
                        set -l env_name $_flag_key

                        # Check if env hook exists in the map - use --arg for safe key
                        if not jq -e --arg k "$env_name" '.env[$k]' $hookfile > /dev/null 2>&1
                            echo "Error: Environment variable hook for '$env_name' not found in $hookfile"
                            return 1
                        end

                        # Unset if currently set
                        if set -q $env_name
                            set -e $env_name
                            echo "Unset environment variable: $env_name (in current session)"
                        end

                        # Remove env hook from map - pass as-is, let __sf_update_root handle escaping
                        if __sf_update_root $PWD "env" "remove" --key "$env_name"
                             echo "Deleted environment variable hook: $env_name from $hookfile"
                        else
                             echo "Error: Failed to delete environment variable hook $env_name" >&2
                             return 1
                        end
                    else # enter or exit
                        # Validate enter/exit command
                        if not set -q _flag_command; or test -z "$_flag_command"
                            echo "Error: --command is required for deleting $hook_type hooks." >&2
                            echo "Usage: smartfish hook delete --type $hook_type --command \"COMMAND\"" >&2
                            return 1
                        end
                        # Use command directly, no need to unescape as we're not doing manual escaping anymore
                        set -l hook_cmd $_flag_command

                        # Check if hook exists - using --arg for safe parameter passing
                        if not jq -e --arg type "$hook_type" --arg hook "$hook_cmd" '.[$type][] | select(. == $hook)' $hookfile > /dev/null 2>&1
                            echo "Error: Hook '$hook_cmd' not found in $hook_type hooks in $hookfile"
                            return 1
                        end

                        # Remove hook - pass as-is, let __sf_update_root handle escaping
                        if __sf_update_root $PWD $hook_type "remove" "$hook_cmd"
                             echo "Deleted $hook_type hook: '$hook_cmd' from $hookfile"
                        else
                            echo "Error: Failed to delete $hook_type hook '$hook_cmd'" >&2
                            return 1
                        end
                    end
                case update
                    # Use argparse to parse arguments
                    argparse --name="smartfish hook update" --min-args=0 'type=' 'old=' 'new=' 'key=' 'value=' -- $argv[3..-1]
                    if test $status -ne 0
                        return 1
                    end

                    # Validate hook type
                    if not set -q _flag_type; or test -z "$_flag_type"
                        echo "Error: --type is required. Must be 'enter', 'exit', or 'env'."
                        echo "Usage: smartfish hook update --type TYPE --old OLD_COMMAND --new NEW_COMMAND"
                        echo "       smartfish hook update --type env --key OLD_KEY --new NEW_KEY"
                        echo "       smartfish hook update --type env --key OLD_KEY --value NEW_VALUE"
                        return 1
                    end
                    if not contains $_flag_type enter exit env
                        echo "Error: Invalid --type. Must be 'enter', 'exit', or 'env'."
                        return 1
                    end
                    set -l hook_type $_flag_type
                    set -l hookfile "$PWD/.smartfish"

                    if test "$hook_type" = "env"
                        # Validate environment variable update parameters
                        if not set -q _flag_key; or test -z "$_flag_key"
                            echo "Error: --key is required for env updates." >&2
                            echo "Usage: smartfish hook update --type env --key OLD_KEY [--new NEW_KEY | --value NEW_VALUE]" >&2
                            return 1
                        end
                        # Use key directly, no need to unescape
                        set -l old_key $_flag_key

                        # Check if --new and --value are mutually exclusive
                        if set -q _flag_new; and set -q _flag_value
                            echo "Error: Cannot specify both --new (new key) and --value (new value) simultaneously."
                            echo "Usage: smartfish hook update --type env --key OLD_KEY --new NEW_KEY"
                            echo "   or: smartfish hook update --type env --key OLD_KEY --value NEW_VALUE"
                            return 1
                        end

                        # Check if at least one of --new or --value is provided
                        if not set -q _flag_new; and not set -q _flag_value
                            echo "Error: At least one of --new or --value is required for env updates."
                            echo "Usage: smartfish hook update --type env --key OLD_KEY [--new NEW_KEY | --value NEW_VALUE]"
                            return 1
                        end

                        # Check if the old environment variable exists in the map - use --arg for safe parameter passing
                        if not jq -e --arg k "$old_key" '.env[$k]' $hookfile > /dev/null 2>&1
                            echo "Error: Environment variable hook for '$old_key' not found in $hookfile"
                            return 1
                        end

                        # Handle key update (only if --new is set)
                        if set -q _flag_new; and test -n "$_flag_new"
                            set -l new_key $_flag_new
                            # Get the current value from the map - use --arg for safe parameter passing
                            set -l current_value (jq -r --arg k "$old_key" '.env[$k]' $hookfile 2>/dev/null)
                            # Remove old key
                            if not __sf_update_root $PWD "env" "remove" --key "$old_key"
                                echo "Error: Failed to remove old key '$old_key' during update" >&2
                                return 1
                            end
                            # Add new key with old value
                             if not __sf_update_root $PWD "env" "add" --key "$new_key" --value "$current_value"
                                echo "Error: Failed to add new key '$new_key' during update" >&2
                                # Attempt to restore old key? Or leave inconsistent state?
                                return 1
                            end
                            # Update the current session
                            if set -q $old_key
                                set -gx "$new_key" "$old_key"
                                set -e $old_key
                            end
                            echo "Updated environment variable hook: key '$old_key' to '$new_key' in $hookfile"

                        # Handle value update (only if --value is set)
                        else if set -q _flag_value; and test -n "$_flag_value"
                            set -l new_value $_flag_value
                            # Update the value in the map (using add which overwrites)
                            if not __sf_update_root $PWD "env" "add" --key "$old_key" --value "$new_value"
                                echo "Error: Failed to update value for key '$old_key'" >&2
                                return 1
                            end

                            # Update the current session
                             set -l final_value $new_value
                            switch $new_value
                                case '@DIR'
                                    set final_value $PWD
                                case '@PARENT'
                                    set final_value (realpath "$PWD/..")
                            end
                            set -gx "$old_key" (eval echo "$final_value")
                            echo "Updated environment variable hook: '$old_key' value to '$new_value' in $hookfile"
                            echo "Set $old_key = $final_value (in current session)"
                        end
                    else # enter or exit
                        # Handle enter/exit hook updates
                        if not set -q _flag_old; or test -z "$_flag_old"
                            echo "Error: --old is required for $hook_type updates." >&2
                            echo "Usage: smartfish hook update --type $hook_type --old OLD_COMMAND --new NEW_COMMAND" >&2
                            return 1
                        end
                        if not set -q _flag_new; or test -z "$_flag_new"
                            echo "Error: --new is required for $hook_type updates." >&2
                            echo "Usage: smartfish hook update --type $hook_type --old OLD_COMMAND --new NEW_COMMAND" >&2
                            return 1
                        end
                        # Use commands directly, no need to unescape
                        set -l old_cmd $_flag_old
                        set -l new_cmd $_flag_new

                        # Check if the old hook exists - use --arg for safe parameter passing
                        if not jq -e --arg type "$hook_type" --arg hook "$old_cmd" '.[$type][] | select(. == $hook)' $hookfile > /dev/null 2>&1
                             echo "Error: Hook '$old_cmd' not found in $hook_type hooks in $hookfile"
                            return 1
                        end

                        # Update the hook (remove old, add new)
                        if not __sf_update_root $PWD $hook_type "remove" "$old_cmd"
                             echo "Error: Failed to remove old $hook_type hook '$old_cmd' during update" >&2
                             return 1
                        end
                         if not __sf_update_root $PWD $hook_type "add" "$new_cmd"
                             echo "Error: Failed to add new $hook_type hook '$new_cmd' during update" >&2
                             # Attempt to restore old hook? Or leave inconsistent state?
                             return 1
                        end
                        echo "Updated $hook_type hook from '$old_cmd' to '$new_cmd' in $hookfile"
                    end
                case list
                    set -l hookfile "$PWD/.smartfish"
                    if not __sf_ensure_file_structure $hookfile # Ensure structure before listing
                         return 1
                    end

                    set -l filter_type
                    if set -q argv[3]
                        set filter_type $argv[3]
                        if test "$filter_type" != "enter" -a "$filter_type" != "exit" -a "$filter_type" != "env"
                            echo "Error: Invalid filter type. Must be 'enter', 'exit', or 'env'"
                            return 1
                        end
                    end

                    set -l hooks_found 0
                    echo "Hooks in $hookfile:"
                    # List Enter hooks
                    if test -z "$filter_type" -o "$filter_type" = "enter"
                        set -l enter_hooks (jq -r '.enter // [] | .[]' "$hookfile" 2>/dev/null)
                        for hook in $enter_hooks
                            set hooks_found 1
                            echo -e "  $(__sf_color blue '(enter)') $hook"
                        end
                    end
                    # List Exit hooks
                    if test -z "$filter_type" -o "$filter_type" = "exit"
                        set -l exit_hooks (jq -r '.exit // [] | .[]' "$hookfile" 2>/dev/null)
                        for hook in $exit_hooks
                            set hooks_found 1
                            echo -e "  $(__sf_color yellow '(exit)') $hook"
                        end
                    end
                     # List Env hooks
                    if test -z "$filter_type" -o "$filter_type" = "env"
                        set -l env_hooks (jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$hookfile" 2>/dev/null)
                        for hook in $env_hooks
                             set hooks_found 1
                            echo -e "  $(__sf_color green '(env)') $hook"
                        end
                    end

                    if test $hooks_found -eq 0
                        if test -n "$filter_type"
                            echo "No $filter_type hooks found in $hookfile"
                        else
                            echo "No hooks found in $hookfile"
                        end
                    end
                case "*"
                    echo "Error: Invalid hook subcommand: $subcmd"
                    echo "Usage: smartfish hook [create|delete|update|list] ..."
                    return 1
            end
        case list
            if set -q argv[2]
                set -l hookfile "$argv[2]"
                if not test -e "$hookfile"
                    echo "Error: .smartfish file '$hookfile' does not exist"
                    return 1
                end
                set -l hooks_found 0
                echo "Hooks in $hookfile:"
                set -l enter_hooks (jq -r '.enter // [] | .[]' "$hookfile" 2>/dev/null)
                set -l exit_hooks (jq -r '.exit // [] | .[]' "$hookfile" 2>/dev/null)
                set -l env_hooks (jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$hookfile" 2>/dev/null)
                for hook in $enter_hooks
                    set hooks_found 1
                    echo -e "  $(__sf_color blue '(enter)') $hook"
                end
                for hook in $exit_hooks
                    set hooks_found 1
                    echo -e "  $(__sf_color yellow '(exit)') $hook"
                end
                for hook in $env_hooks
                    set hooks_found 1
                    echo -e "  $(__sf_color green '(env)') $hook"
                end
                if test $hooks_found -eq 0
                    echo "No hooks found in $hookfile"
                end
            else
                __sf_list_hooks_as_table
            end
        case reset
            echo "Resetting active smartfish hooks"
            set -g __sf_active_smartfish ""
            set -l roots (__sf_find_all_roots $PWD)
            set -g __sf_active_smartfish $roots
            for root in $roots
                set -l root_file (string split "|" $root)[1]
                set -l root_dir (string split "|" $root)[2]
                __sf_process_hooks "enter" $root_file $root_dir
            end
            echo "Reset active smartfish hooks"
        case "*"
            echo "Error: Unknown command: $argv[1]"
            __sf_usage
            return 1
    end
end

# Updated usage function
function __sf_usage
    echo "SmartFish (v$__sf_format_version) - Directory-aware hooks for Fish shell"
    echo ""
    echo "Usage: smartfish COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  active list             List active .smartfish files"
    echo "  active activate [PATH|--all]  Activate a single .smartfish file or all files"
    echo "  debug                   Toggle debug mode"
    echo "  hook create --type enter|exit --command \"COMMAND\"  Create an enter or exit hook (quote command if it has spaces)"
    echo "  hook create --type env --key NAME --value VALUE    Create an environment variable"
    echo "  hook delete --type enter|exit --command \"COMMAND\"  Delete an enter or exit hook (quote command if it has spaces)"
    echo "  hook delete --type env --key KEY              Delete an environment variable"
    echo "  hook update --type enter|exit --old \"OLD_CMD\" --new \"NEW_CMD\"  Update an enter/exit hook (quote commands)"
    echo "  hook update --type env --key KEY --new NEW_KEY       Rename an environment variable key"
    echo "  hook update --type env --key KEY --value NEW_VALUE    Update an environment variable value"
    echo "  hook list [enter|exit|env]  List hooks in local .smartfish file, optionally filtered by type"
    echo "  list [PATH]             List hooks in directory tree or a specific .smartfish file"
    echo "  reset                   Reset active .smartfish hooks"
    echo "  help                    Show this help message"
    echo ""
    echo "Special values for --value:"
    echo "  @DIR                    Current directory path"
    echo "  @PARENT                 Parent directory path"
    echo ""
    echo "Examples:"
    echo "  smartfish hook create --type enter --command \"echo 'hello world'\""
    echo "  smartfish hook create --type env --key API_KEY --value 12345"
    echo "  smartfish hook delete --type env --key API_KEY"
    echo "  smartfish hook update --type env --key API_KEY --value 67890"
    echo "  smartfish hook update --type env --key API_KEY --new SECRET_KEY"
    echo ""
    echo "NOTE: Env vars are now stored in a dedicated 'env' map in .smartfish."
    echo "      Existing files using 'set -gx' in 'enter'/'exit' need manual migration."
end

# Updated completions for smartfish
# Top-level commands (no short versions)
complete -f -c smartfish -n "__fish_use_subcommand" -a "active\t'Manage active .smartfish files' debug\t'Toggle debug mode' hook\t'Manage hooks' list\t'List hooks in directory tree or file' reset\t'Reset active hooks' help\t'Show help message'"

# Completions for active subcommand
complete -f -c smartfish -n "__fish_seen_subcommand_from active; and not __fish_seen_subcommand_from list activate" -a "list\t'List active .smartfish files' activate\t'Activate a .smartfish file'"
complete -f -c smartfish -n "__fish_seen_subcommand_from active; and __fish_seen_subcommand_from activate" -a "(__sf_get_smartfish_files) --all\t'Activate all .smartfish files'"

# Completions for hook subcommand
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and not __fish_seen_subcommand_from create delete update list" -a "create\t'Create a new hook' delete\t'Delete an existing hook' update\t'Update an existing hook' list\t'List hooks in local .smartfish file'"

# Completions for hook create
# Suggest --type first
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and not contains -- --type (commandline -opc)" -a "--type\t'Hook type (enter, exit, env)'"
# Complete type values after --type
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and string match -q -- '--type' -- (commandline -opc)[-1]" -a "enter\t'Enter hook' exit\t'Exit hook' env\t'Environment variable hook'"

# Suggest --command if type is enter/exit
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and contains -- --type (commandline -opc); and contains -- enter (commandline -opc); and not contains -- --command (commandline -opc)" -a "--command\t'Hook command'"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and contains -- --type (commandline -opc); and contains -- exit (commandline -opc); and not contains -- --command (commandline -opc)" -a "--command\t'Hook command'"

# Suggest --key and --value if type is env
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and contains -- --type (commandline -opc); and contains -- env (commandline -opc); and not contains -- --key (commandline -opc)" -a "--key\t'Variable name'"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and contains -- --type (commandline -opc); and contains -- env (commandline -opc); and not contains -- --value (commandline -opc)" -a "--value\t'Variable value'"

# Complete special values after --value for env type
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and string match -q -- '--value' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a "@DIR\t'Current directory path' @PARENT\t'Parent directory path'"

# Disable file completions after --command for enter/exit
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and string match -q -- '--command' -- (commandline -opc)[-1]; and not contains -- --key (commandline -opc); and not contains -- --value (commandline -opc)" -a ""

# Disable file completions after --key or --value for env
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and string match -q -- '--key' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a ""
complete -f -c smartfish -n "__fish_seen_subcommand_from hook create; and string match -q -- '--value' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a ""

# Completions for hook delete
# Initially suggest --type
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and not contains -- --type (commandline -opc)" -a "--type\t'Hook type (enter, exit, env)'"

# Complete type values ONLY when the previous token was --type
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and string match -q -- '--type' -- (commandline -opc)[-1]" -a "enter\t'Enter hook' exit\t'Exit hook' env\t'Environment variable hook'"

# Suggest --command if type is enter/exit
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and contains -- --type (commandline -opc); and contains -- enter (commandline -opc); and not contains -- --command (commandline -opc)" -a "--command\t'Hook command to delete'"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and contains -- --type (commandline -opc); and contains -- exit (commandline -opc); and not contains -- --command (commandline -opc)" -a "--command\t'Hook command to delete'"

# Suggest --key if type is env
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and contains -- --type (commandline -opc); and contains -- env (commandline -opc); and not contains -- --key (commandline -opc)" -a "--key\t'Environment variable key to delete'"

# Complete command values after --command, checking specific type from command line
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and string match -q -- '--command' -- (commandline -opc)[-1]; and contains -- --type enter (commandline -opc)" -a "(__sf_get_hooks_for_completion $PWD/.smartfish enter)"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and string match -q -- '--command' -- (commandline -opc)[-1]; and contains -- --type exit (commandline -opc)" -a "(__sf_get_hooks_for_completion $PWD/.smartfish exit)"

# Complete key values after --key for env 
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from delete; and string match -q -- '--key' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a "(__sf_get_env_for_completion $PWD/.smartfish)"

# Completions for hook update
# Initially, only suggest --type
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and not contains -- --type (commandline -opc)" -a "--type\t'Hook type (enter, exit, env)'"

# Complete type values ONLY when the previous token was --type
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--type' -- (commandline -opc)[-1]" -a "enter\t'Enter hook' exit\t'Exit hook' env\t'Environment variable hook'"

# Suggest --old if type is enter/exit and --old is not present
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- enter (commandline -opc); and not contains -- --old (commandline -opc)" -a "--old\t'Old command'"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- exit (commandline -opc); and not contains -- --old (commandline -opc)" -a "--old\t'Old command'"
# Suggest --new if type is enter/exit and --new is not present
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- enter (commandline -opc); and not contains -- --new (commandline -opc)" -a "--new\t'New command'"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- exit (commandline -opc); and not contains -- --new (commandline -opc)" -a "--new\t'New command'"

# Complete old command values after --old for enter/exit
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--old' -- (commandline -opc)[-1]; and contains -- --type enter (commandline -opc)" -a "(__sf_get_hooks_for_completion $PWD/.smartfish enter)"
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--old' -- (commandline -opc)[-1]; and contains -- --type exit (commandline -opc)" -a "(__sf_get_hooks_for_completion $PWD/.smartfish exit)"

# Disable file completions after --new for enter/exit
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--new' -- (commandline -opc)[-1]; and contains -- --type enter (commandline -opc)" -a ""
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--new' -- (commandline -opc)[-1]; and contains -- --type exit (commandline -opc)" -a ""

# Suggest --key if type is env and --key is not present
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- env (commandline -opc); and not contains -- --key (commandline -opc)" -a "--key\t'Old environment variable key'"
# Suggest --new (new key) if type is env and --new is not present
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- env (commandline -opc); and not contains -- --new (commandline -opc)" -a "--new\t'New environment variable key'"
# Suggest --value (new value) if type is env and --value is not present
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and contains -- --type (commandline -opc); and contains -- env (commandline -opc); and not contains -- --value (commandline -opc)" -a "--value\t'New environment variable value'"

# Complete old env keys after --key for env
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--key' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a "(__sf_get_env_for_completion $PWD/.smartfish)"

# Complete special values after --value for env
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--value' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a "@DIR\t'Current directory path' @PARENT\t'Parent directory path'"

# Disable file completions after --new (new key) for env
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from update; and string match -q -- '--new' -- (commandline -opc)[-1]; and contains -- --type env (commandline -opc)" -a ""

# Completions for hook list - suggest enter/exit/env filter types
complete -f -c smartfish -n "__fish_seen_subcommand_from hook; and __fish_seen_subcommand_from list; and __fish_is_nth_token 3" -a "enter\t'Enter hooks' exit\t'Exit hooks' env\t'Environment variable hooks'"

# Completions for list
complete -f -c smartfish -n "__fish_seen_subcommand_from list; and __fish_is_nth_token 2" -a "(__sf_get_smartfish_files)"
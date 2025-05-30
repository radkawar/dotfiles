function toggle_prompt -d "Toggle between different fish prompt styles"
    # Available styles
    set -l styles "two-line" "single-line" "minimal"
    set -l make_global false
    
    # Parse arguments
    set -l remaining_args
    for arg in $argv
        switch $arg
            case --global
                set make_global true
            case '*'
                set remaining_args $remaining_args $arg
        end
    end
    
    # If no argument provided, cycle through styles
    if test (count $remaining_args) -eq 0
        if not set -q FISH_PROMPT_STYLE
            set -g FISH_PROMPT_STYLE two-line
        end
        
        # Find current style index
        set -l current_index 1
        for i in (seq (count $styles))
            if test $styles[$i] = $FISH_PROMPT_STYLE
                set current_index $i
                break
            end
        end
        
        # Get next style (cycle back to first if at end)
        set -l next_index (math "$current_index % "(count $styles)" + 1")
        
        if test $make_global = true
            # Clear any existing global variable and set universal
            set -e FISH_PROMPT_STYLE  # Erase global variable
            set -U FISH_PROMPT_STYLE $styles[$next_index]
            echo "Prompt style changed to: $styles[$next_index] (global)"
        else
            set -g FISH_PROMPT_STYLE $styles[$next_index]
            echo "Prompt style changed to: $styles[$next_index]"
        end
    else
        # Set specific style if provided
        set -l requested_style $remaining_args[1]
        if contains $requested_style $styles
            if test $make_global = true
                # Clear any existing global variable and set universal
                set -e FISH_PROMPT_STYLE  # Erase global variable
                set -U FISH_PROMPT_STYLE $requested_style
                echo "Prompt style set to: $requested_style (global)"
            else
                set -g FISH_PROMPT_STYLE $requested_style
                echo "Prompt style set to: $requested_style"
            end
        else
            echo "Invalid style. Available styles:"
            for style in $styles
                echo "  - $style"
            end
            return 1
        end
    end
    
    echo "Available styles: two-line | single-line | minimal"
    echo "Use --global flag to persist across sessions"
end 
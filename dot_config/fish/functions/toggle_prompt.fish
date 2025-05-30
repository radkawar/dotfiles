function toggle_prompt -d "Toggle between different fish prompt styles"
    # Available styles
    set -l styles "two-line" "single-line" "minimal"
    
    # If no argument provided, cycle through styles
    if test (count $argv) -eq 0
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
        set -g FISH_PROMPT_STYLE $styles[$next_index]
        
        echo "Prompt style changed to: $FISH_PROMPT_STYLE"
    else
        # Set specific style if provided
        set -l requested_style $argv[1]
        if contains $requested_style $styles
            set -g FISH_PROMPT_STYLE $requested_style
            echo "Prompt style set to: $FISH_PROMPT_STYLE"
        else
            echo "Invalid style. Available styles:"
            for style in $styles
                echo "  - $style"
            end
            return 1
        end
    end
    
    echo "Available styles: two-line | single-line | minimal"
end 
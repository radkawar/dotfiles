function fish_right_prompt
    # Get prompt style
    set -l prompt_style two-line
    if set -q FISH_PROMPT_STYLE
        set prompt_style $FISH_PROMPT_STYLE
    end
    
    # Don't show right prompt on narrow terminals (except for two-line which needs AWS)
    set term_width (tput cols)
    if test $prompt_style != "two-line" -a $term_width -lt 100
        return
    end
    
    set -l right_parts
    
    # # AWS Profile info - format long profiles nicely
    # if set -q AWS_PROFILE
    #     # Handle long AWS profile names like "000000000000/root" or "000000000000/user:dummy"
    #     if string match -q "*/*" $AWS_PROFILE
    #         set parts (string split "/" $AWS_PROFILE)
    #         set account $parts[1]
    #         set role $parts[2]
    #         # Abbreviate long account numbers: 307946636100 -> 307...100
    #         if test (string length $account) -gt 8
    #             set account_short (string sub -l 3 $account)"..."(string sub -s -3 $account)
    #             set right_parts $right_parts (set_color yellow)"[$account_short/$role]"(set_color normal)
    #         else
    #             set right_parts $right_parts (set_color yellow)"[$AWS_PROFILE]"(set_color normal)
    #         end
    #     else
    #         set right_parts $right_parts (set_color yellow)"[$AWS_PROFILE]"(set_color normal)
    #     end
    # end
    
    # For single-line and minimal only, add duration and status
    if test $prompt_style != "two-line"
        # Command duration if significant
        if test -n "$CMD_DURATION" -a "$CMD_DURATION" -gt 1000
            set duration_s (math --scale=1 "$CMD_DURATION / 1000")
            set right_parts $right_parts (set_color blue)"$duration_s"s""(set_color normal)
        end
        
        # Last command status - only show errors
        set last_status $status
        if test $last_status -ne 0
            set right_parts $right_parts (set_color red)"✗"(set_color normal)
        end
    end
    
    # Join parts with clean spacing if we have any
    if test (count $right_parts) -gt 0
        for i in (seq (count $right_parts))
            echo -n $right_parts[$i]
            if test $i -lt (count $right_parts)
                echo -n " "
            end
        end
    end
end 
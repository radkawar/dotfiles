set -g nooverride PATH PWD
set -g wasset

function -v PWD onchdir
    set -g wasset

    set current_dir $PWD
    while [ "$current_dir" != / ]
        for env_file in $current_dir/.setenv-*
            if not test -e $env_file
                continue
            end

            set env_name (string replace -r '^.+\.setenv-' '' (basename $env_file))

            if contains $env_name $nooverride
                continue
            end

            if not test -s $env_file
                set env_value (realpath $current_dir)
            else if test -L $env_file; and test -d $env_file
                set env_value (realpath $env_file)
            else
                set env_value (cat $env_file)
            end

            if not contains $env_name $wasset
                set -ga wasset $env_name
                set -gx $env_name $env_value
                echo "Setting $env_name = $env_value"
            end
        end

        set current_dir (realpath $current_dir/..)
    end
end

onchdir

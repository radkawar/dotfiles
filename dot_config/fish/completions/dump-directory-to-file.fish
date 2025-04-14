complete -c dump-directory-to-file -f -n "test (count (commandline -opc)) -eq 1" -a "(__fish_complete_directories)"
complete -c dump-directory-to-file -f -n "test (count (commandline -opc)) -eq 2" -a "(__fish_complete_path)"
complete -c dump-directory-to-file -f -n "test (count (commandline -opc)) -gt 2" -a ""

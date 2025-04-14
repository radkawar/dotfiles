function _chezmoi_refresh
    set -x REFRESH_AWS "true"
    chezmoi apply
    set -e REFRESH_AWS
end
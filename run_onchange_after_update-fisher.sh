#!/usr/bin/env fish

if not functions -q fisher
    echo "Fisher is not installed. Installing..."

    echo "Installing fisher..."
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
end

# fish_plugins hash: {{ include "fish/fish_plugins" | sha256sum }}
fisher update
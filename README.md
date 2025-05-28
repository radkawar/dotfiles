# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Installation

### macOS

1. Install Homebrew: https://brew.sh/
2. Install chezmoi and apply dotfiles:
   ```bash
   brew install chezmoi
   chezmoi init --apply $GITHUB_USERNAME
   ```

### Linux (Ubuntu/Debian)

1. Install chezmoi:

   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin
   ```

2. For servers (minimal installation without GUI apps):

   ```bash
   export CHEZMOI_SERVER=true
   chezmoi init --apply radkawar
   ```

3. For desktops (full installation):
   ```bash
   chezmoi init --apply radkawar
   ```

## OS-Specific Handling

- **macOS**: Uses Homebrew for all package management
- **Linux**: Uses native package managers (apt) for better ARM64 support
- **Server Detection**: Set `CHEZMOI_SERVER=true` to skip GUI applications

## Package Differences

### Core packages (all systems):

- fish, tmux, neovim, git, ripgrep, fd, fzf
- go, node, python
- aws-cli, chezmoi

### macOS-only:

- GUI apps: Alacritty, WezTerm, 1Password
- Development: Pulumi, GitUI, Terraform
- VS Code extensions

### Linux servers (minimal):

- No GUI applications
- No Pulumi, GitUI
- System packages from apt

## Key Files

- `dot_homebrew/Brewfile.tmpl` - macOS package list
- `run_onchange_install-linux-packages.sh.tmpl` - Linux package installation
- `run_onchange_install-packages.sh.tmpl` - macOS Homebrew installation

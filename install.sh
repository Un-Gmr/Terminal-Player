#!/bin/bash
set -e

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

echo "Detected OS: $OS"

install_deps_ubuntu_debian() {
    sudo apt update
    sudo apt install -y mpv yt-dlp jq curl imagemagick figlet jp2a socat python3 python3-pip
    pip3 install syncedlyrics --break-system-packages
}

install_deps_arch() {
    sudo pacman -Syu --needed mpv yt-dlp jq curl imagemagick figlet jp2a socat python python-pip
    pip3 install syncedlyrics --break-system-packages
}

install_deps_fedora() {
    sudo dnf install -y mpv yt-dlp jq curl ImageMagick figlet jp2a socat python3 python3-pip
    pip3 install syncedlyrics --break-system-packages
}

install_deps_macos() {
    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found. Please install: https://brew.sh/"
        exit 1
    fi
    brew update
    brew install mpv yt-dlp jq curl imagemagick figlet jp2a socat python
    python3 -m pip install --user --upgrade pip
    pip3 install syncedlyrics --break-system-packages
}

install_scripts_linux() {
    SOURCE_PATH="$(pwd)"
    declare -A scripts=( ["play"]="play.sh" ["playlist"]="playlist.sh" )
    DEST_DIR="/usr/local/bin"

    for cmd in "${!scripts[@]}"; do
        SCRIPT="${SOURCE_PATH}/${scripts[$cmd]}"
        DEST="${DEST_DIR}/${cmd}"

        if [ ! -f "$SCRIPT" ]; then
            echo "Error: ${scripts[$cmd]} not found in current directory"
            exit 1
        fi

        echo "Installing ${scripts[$cmd]} to $DEST"
        sudo install -m 755 "$SCRIPT" "$DEST"
    done

    echo "Installation complete! You can now run 'play' and 'playlist' from anywhere"
}

@echo off
bash "%DEST%" %*
EOL
    done

    echo "You can now run 'play' and 'playlist' from Git Bash, CMD, or PowerShell"
    export PATH=\"$HOME/bin:\$PATH\"
}

case "$OS" in
    ubuntu|debian) install_deps_ubuntu_debian && install_scripts_linux ;;
    arch|manjaro) install_deps_arch && install_scripts_linux ;;
    fedora) install_deps_fedora && install_scripts_linux ;;
    Darwin) install_deps_macos && install_scripts_linux ;;
    *) echo "OS not recognized. Only Linux/macOS/Windows supported." ; exit 1 ;;
esac
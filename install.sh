#!/bin/bash
set -e

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    OS_NAME=$(uname -s)
fi

echo "Detected OS: $OS_NAME"

echo "Installing dependencies"
case "$OS_NAME" in
    ubuntu|debian)
        sudo apt update
        sudo apt install -y mpv yt-dlp jq curl imagemagick figlet jp2a socat python3 python3-pip
        pip3 install --upgrade pip
        pip3 install syncedlyrics
        ;;
    arch)
        sudo pacman -Syu --needed mpv yt-dlp jq curl imagemagick figlet jp2a socat python python-pip
        pip install --upgrade pip
        pip install syncedlyrics
        ;;
    fedora)
        sudo dnf install -y mpv yt-dlp jq curl ImageMagick figlet jp2a socat python3 python3-pip
        pip3 install --upgrade pip
        pip3 install syncedlyrics
        ;;
    Darwin)
        echo "macOS detected. Make sure Homebrew is installed"
        brew update
        brew install mpv yt-dlp jq curl imagemagick figlet jp2a socat python
        pip3 install --upgrade pip
        pip3 install syncedlyrics
        ;;
    *)
        echo "OS not recognized. If you are on Windows, this script isn’t available"
        ;;
esac

SOURCE_PATH="$(pwd)"
PLAY_NAME="play"
PLAY_SCRIPT="$SOURCE_PATH/$PLAY_NAME.sh"
PLAYLIST_NAME="playlist"
PLAYLIST_SCRIPT="$SOURCE_PATH/$PLAYLIST_NAME.sh"
PLAY_DEST_PATH="/usr/local/bin/$PLAY_NAME"
PLAYLIST_DEST_PATH="/usr/local/bin/$PLAYLIST_NAME"
EXIT=0

if [ ! -f "$PLAY_SCRIPT" ]; then
  echo "Error: play.sh not found in the current directory"
  EXIT=1
fi

if [ ! -f "$PLAYLIST_SCRIPT" ]; then
  echo "Error: playlist.sh not found in the current directory"
  EXIT=1
fi

if [ $EXIT -eq 1 ]; then
  exit 1
fi

sudo rm -f "$PLAY_DEST_PATH"
sudo rm -f "$PLAYLIST_DEST_PATH"

echo "Moving play.sh to $PLAY_DEST_PATH"
sudo cp "$PLAY_SCRIPT" "$PLAY_DEST_PATH"
sudo chmod +x "$PLAY_DEST_PATH"

echo "Moving playlist.sh to $PLAYLIST_DEST_PATH"
sudo cp "$PLAYLIST_SCRIPT" "$PLAYLIST_DEST_PATH"
sudo chmod +x "$PLAYLIST_DEST_PATH"

echo "Installation complete You can now run 'play' and 'playlist' from anywhere"
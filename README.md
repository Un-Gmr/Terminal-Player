# Terminal-Player
An cli based music player

- [Installation](#installation)
- [Usage](#Usage)

## Installation
### Linux / MacOs
install git(if not already):
```bash
# Arch linux / Manjaro
sudo pacman -S git
```
```bash
# Ubuntu / Debian
sudo apt install git
```
```bash
# Fedora
sudo dnf install git
```
```bash
# Macos
# Install homebrew (if not already):
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
source ~/.bash_profile
# Git
brew install git
```

```bash
git clone https://github.com/Un-Gmr/Terminal-Player
cd Terminal-Player
./install.sh
```

### Windows (Beta)
```powershell
# Install git and git-bash
winget install --id Git.Git -e --source winget
```
```powershell
git clone https://github.com/Un-Gmr/Terminal-Player
cd Terminal-Player
& "C:\Program Files\Git\bin\bash.exe" install.sh
```

## Usage
### Play
play search terms [-l]  
The script will automaticly use the first result on youtube and play it without video  
stop the song with 's'

### Playlist
playlist filename [-l] [-s]  
Put files in ~/.local/share/play/playlists e.g. likes.txt and play them with "playlist likes [-l] [-s]"  
skip song with 's' quit with 'q'

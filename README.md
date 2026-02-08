# Terminal-Player
An cli based music player
> Note: All required dependencies are installed automatically by `install.sh`  
> Note: You need sudo / admin privileges to use `install.sh`

- [Installation](#installation)
- [Usage](#usage)
- [Instalation experimental](#experimental)

# Install
## Linux / MacOS
```bash
tar -xf Terminal-Player-v1.0.0.tar.xz
cd Terminal-Player
./install.sh
```
## Windows
```powershell
Invoke-WebRequest -Uri "https://github.com/Un-Gmr/Terminal-Player/releases/download/v1.0.0/Terminal-Player-v1.0.0.zip" -OutFile "Terminal-Player-v1.0.0.zip"
Expand-Archive Terminal-Player-v1.0.0.zip
cd Terminal-Player
install.bat
```

# Usage
## Play:
play search terms [-l]  
-l flag: loop the song  
The script will automaticaly use the first result on youtube and play it without video  
stop the song with 's'

## Playlist:
playlist filename [-l] [-s]  
-l flag: loop the playlist  
-s flag: shuffle the playlist  
Put files in ~/.local/share/play/playlists e.g. likes.txt and play them with "playlist likes [-l] [-s]"  
skip song with 's' quit with 'q'

# Experimental
## Linux / MacOs
install git (if not already):  
Arch linux / Manjaro:
```bash
sudo pacman -S git
```
Ubuntu / Debian:
```bash
sudo apt install git
```
Fedora:
```bash
sudo dnf install git
```
MacOS:
```bash
# Install homebrew (if not already):
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
source ~/.bash_profile
# Install Git:
brew install git
```
Clone the repo and install:
```bash
git clone https://github.com/Un-Gmr/Terminal-Player
cd Terminal-Player
./install.sh
```

## Windows
Install git and git-bash:
```powershell
winget install --id Git.Git -e --source winget
```
Clone the repo and install:
```powershell
git clone https://github.com/Un-Gmr/Terminal-Player
cd Terminal-Player
& "C:\Program Files\Git\bin\bash.exe" install.sh
```

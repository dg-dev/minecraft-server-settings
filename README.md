# minecraft-server-settings
Minecraft Server Bedrock Settings

## About
This is mostly a small, personal project to learn some systemd. Currently a work in progress but once complete will consists of scripts, settings and systemd units for running a basic Minecraft Bedrock server on Linux as a systemd service that can perform automatic backups.

## Installation
* Create dirs /opt/minecraft/{backup,server,temporary,utilities}
* Copy scripts to /opt/minecraft/utilities and confirm they're executable
* Copy systemd units to /etc/systemd/system and do a systemctl daemon-reload
* Download the latest Minecraft Bedrock server and extract it into a separate dir inside /opt/minecraft/server
* Create a symlink called "latest" that points to the above server dir (example: ln -s /opt/minecraft/server/bedrock-server-1.20.73.01 /opt/minecraft/server/latest)
* Overwrite the default server settings with the ones included here and make any additional changes
* Enable and start the minecraft.service

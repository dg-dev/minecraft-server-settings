#!/bin/sh

server_dir=/opt/minecraft/server

download_url="${1:?download_url}"
download_name="$(basename "$download_url" .zip)"
download_zip="${download_name}.zip"
cd "$server_dir"
[ -d "$download_name" ] && exit 1 
[ ! -f "$download_zip" ] && { \
        wget "$download_url" -O "$download_zip" || exit 2
    }
mkdir -p "$download_name"
unzip -d "$download_name" "$download_zip" || exit 3
cp -a "latest/worlds" \
    "latest/server.properties" \
    "latest/permissions.json" \
    "latest/allowlist.json" \
    "$download_name"
systemctl stop minecraft.service
[ -L "latest" ] && rm latest
ln -s "$download_name" latest
chown -R minecraft:minecraft latest "$download_name" "$download_zip"
systemctl start minecraft.service


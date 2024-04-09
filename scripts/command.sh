#!/bin/sh

minecraft_fifo_path=/opt/minecraft/temporary/minecraft.stdin

if [ -p "$minecraft_fifo_path" ];
then
	echo "$*" > "$minecraft_fifo_path"
else
	exit 1
fi

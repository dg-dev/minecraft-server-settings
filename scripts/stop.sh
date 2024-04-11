#!/bin/sh

max_attempts=300
command_path=/opt/minecraft/scripts/command.sh

[ -z "$1" ] && exit 1

"$command_path" stop

c=0
while [ "$(ps -p "$1" -o comm=)" = "bedrock_server" ]
do
    sleep 1
    c=$(expr $c + 1)
    [ "$c" -ge "$max_attempts" ] && exit 2
done

exit 0

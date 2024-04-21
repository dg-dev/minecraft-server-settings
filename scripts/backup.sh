#!/bin/sh


backups_dir=/opt/minecraft/backup
command_path=/opt/minecraft/scripts/command.sh
time_limit_sec=60
debug=2

debug_print() {
    debug_level="${1:?debug_level}"
    shift
    [ "$debug_level" -le "${debug:-0}" ] && echo "$*"
}

backup_state=0
debug_print 3 '$backup_state: '"$backup_state"
start_epoch=$(date +%s)
start_cursor=$(journalctl -u minecraft.service --show-cursor -n 0 | grep '^-- cursor: ' | cut -f 3 -d ' ')
debug_print 4 '$start_cursor: '"$start_cursor"
file_list=""
debug_print 3 '$file_list:'"$file_list"


while [ "$(expr "$(date +%s)" - "$start_epoch")" -lt "$time_limit_sec" ]; do
    [ -z "$start_cursor" ] && exit 1

    if [ "$backup_state" -eq 0 ]; then
        debug_print 2 ">>> save resume"
        "${command_path}" save resume
        sleep 1
        debug_print 2 ">>> save hold"
        "${command_path}" save hold
        backup_state=1
        debug_print 3 '$backup_state: '"$backup_state"
    fi

    while read -r LINE; do
        case "$LINE" in
            '-- cursor: '* )
                debug_print 4 "LINE (${backup_state}): $LINE"
                start_cursor="$(echo "$LINE" | cut -f '3' -d ' ')"
                debug_print 4 '$start_cursor: '"$start_cursor"
                ;;
            *'Saving...' )
                case "$backup_state" in
                    1 )
                        debug_print 1 "LINE (${backup_state}): $LINE"
                        debug_print 2 ">>> save query"
                        "${command_path}" save query
                        backup_state=2
                        debug_print 3 '$backup_state: '"$backup_state"
                        ;;
                    * )
                        debug_print 1 "<LINE> (${backup_state}): $LINE"
                        ;;
                esac
                ;;
            *'Data saved. Files are now ready to be copied.' )
                case "$backup_state" in
                    2 )
                        debug_print 1 "LINE (${backup_state}): $LINE"
                        debug_print 2 ">>> save query"
                        "${command_path}" save query
                        backup_state=3
                        debug_print 3 '$backup_state: '"$backup_state"
                        ;;
                    3 )
                        debug_print 1 "LINE (${backup_state}): $LINE"
                        debug_print 3 '$file_list: '"$file_list"
                        # backup the files on the list here
                        debug_print 2 ">>> save resume"
                        "$command_path" save resume
                        backup_state=4
                        debug_print 3 '$backup_state: '"$backup_state"
                        ;;
                    * )
                        debug_print 1 "<LINE> (${backup_state}): $LINE"
                        ;;
                    esac
                ;;
            *'A previous save has not been completed.' )
                case "$backup_state" in
                    2 )
                        debug_print 1 "LINE (${backup_state}): $LINE"
                        debug_print 2 ">>> save query"
                        "${command_path}" save query
                        ;;
                    * )
                        debug_print 1 "<LINE> (${backup_state}): $LINE"
                        ;;
                    esac
                ;;
            [![]* )
                case "$backup_state" in
                    3 )
                        debug_print 1 "LINE (${backup_state}): $LINE"
                        file_list="${file_list}$LINE"
                        debug_print 3 '$file_list: '"$file_list"
                        ;;
                    * )
                        debug_print 1 "<LINE> (${backup_state}): $LINE"
                        ;;
                    esac
                ;;
            *'Changes to the world are resumed.' )
                case "$backup_state" in
                    4 )
                        debug_print 1 "LINE (${backup_state}): $LINE"
                        exit 0
                        ;;
                    * )
                        debug_print 1 "<LINE> (${backup_state}): $LINE"
                        ;;
                    esac
                ;;
            * )
                debug_print 1 "<LINE> (${backup_state}): $LINE"
                ;;
        esac
    done << EOT
$(journalctl -u minecraft.service --after-cursor "$start_cursor" -o cat --no-pager --show-cursor)
EOT
    sleep 1
done

if [ "$backup_state" -gt 0 ]; then
    debug_print 2 ">>> save resume"
    "$command_path" save resume
fi

exit 2

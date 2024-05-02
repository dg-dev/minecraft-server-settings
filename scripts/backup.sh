#!/bin/sh

server_dir=/opt/minecraft/server/latest
backup_dir=/opt/minecraft/backup
temporary_dir=/opt/minecraft/temporary
command_path=/opt/minecraft/scripts/command.sh
time_limit_sec=60
debug=2

debug_print() {
    debug_level="${1:?debug_level}"
    shift
    [ "$debug_level" -le "${debug:-0}" ] && echo "$*"
}

backup_simple() {
    prepared_dir="${1:?prepared_dir}"
    prepared_name="$(basename "$prepared_dir")"
    backup_dir_simple="${backup_dir}/simple"
    mkdir -p "$backup_dir_simple"
    # tar/gzip the whole temp folder
    # move tar.gz to backup_dir only if no errors found during entire process
    tar czf "${backup_dir_simple}/${prepared_name}.tar.gz" \
        -C "$temporary_dir" "$prepared_name"
}

prepare_world_files() {
    world_files="${1:?world_files}"
    # create temp dir e.g., 20240428191654 ensuring it's unique
    world_backup_name=""
    until [ ! -z "$world_backup_name" ] && \
            [ ! -d "${temporary_dir}/$world_backup_name" ] && \
            [ ! -d "${backup_dir}/${world_backup_name}.tar.gz" ]; do
        [ -z "$world_backup_name" ] || sleep 1
        world_backup_name="$(date '+%Y-%m-%d_%H%M%S')"
    done
    server_base_dir="${server_dir}/worlds"
    temporary_base_dir="${temporary_dir}/${world_backup_name}"
    mkdir -p "$temporary_base_dir"
    # iterate over $world_files
    while IFS=':' read -r world_file_path world_file_size 0<&5; do
        echo "$world_file_path" --- "$world_file_size"
        [ -z "$world_file_path" ] || [ -z "$world_file_size" ] && continue
        # create world dirs
        current_temporary_file="${temporary_base_dir}/$world_file_path"
        current_temporary_dir="$(dirname "$current_temporary_file")"
        current_server_file="${server_base_dir}/${world_file_path}"
        current_server_dir="$(dirname "$current_server_file")"
        mkdir -p "$current_temporary_dir"
        # copy files
        cp "$current_server_file" "${current_temporary_dir}/"
        # truncate files
        truncate "$current_temporary_file" -s "$world_file_size"
        # restore timestamps
        touch -r "$current_server_file" "$current_temporary_file"
        touch -r "$current_server_dir" "$current_temporary_dir"
    done 5<<EOT
$(echo "$world_files" | sed 's/, \{0,1\}/\n/g')
EOT
    # backup
    mkdir -p "$backup_dir"
    backup_simple "$temporary_base_dir"
    # clean up
    [ ! -z "$temporary_dir" ] && [ ! -z "$world_backup_name" ] && \
        rm -rf "$temporary_base_dir"
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
                        prepare_world_files "$file_list"
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

#!/bin/sh

server_dir=/opt/minecraft/server/latest
backup_dir=/opt/minecraft/backup
prepared_dir=/opt/minecraft/backup/prepared
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
    prepared_name="${1:?prepared_name}"
    prepared_dir="${2:?prepared_dir}"
    backup_dir_simple="${backup_dir}/simple"
    mkdir -p "$backup_dir_simple"
    # tar/gzip the whole temp folder
    # move tar.gz to backup_dir only if no errors found during entire process
    tar czf "${backup_dir_simple}/${prepared_name}.tar.gz" \
        -C "$prepared_dir" .
}

backup_hardlinked() {
    prepared_name="${1:?prepared_name}"
    prepared_dir="${2:?prepared_dir}"
    backup_dir_hardlinked="${backup_dir}/hardlinked"
    backup_dir_path="${backup_dir_hardlinked}/${prepared_name}"
    backup_dir_link="${backup_dir_hardlinked}/last"
    mkdir -p "$backup_dir_hardlinked"
    mkdir -p "$backup_dir_path"
    find "$prepared_dir" -type f -mindepth 1 -exec sh -c '
        relative_path="$(realpath --relative-to="'"$prepared_dir"'" "{}")"
        backup_last_dir="$(realpath "'"$backup_dir_link"'")"
        backup_new_dir="'"$backup_dir_path"'"
        current_last_path="${backup_last_dir}/${relative_path}"
        current_last_dir="$(dirname "$current_last_path")"
        current_new_path="${backup_new_dir}/${relative_path}"
        current_new_dir="$(dirname "$current_new_path")"
        mkdir -p "$current_new_dir"
        cmp -s "{}" "$current_last_path" && \
            ln "$current_last_path" "$current_new_path" || \
            cp "{}" "$current_new_path"
        ' \;
    [ -L "$backup_dir_link" ] && rm "$backup_dir_link"
    ln -s "$backup_dir_path" "$backup_dir_link"
}

backup_hardlinkedblobs() {
    prepared_name="${1:?prepared_name}"
    prepared_dir="${2:?prepared_dir}"
    backup_dir_hardlinkedblobs="${backup_dir}/hardlinkedblobs"
    backup_dir_blobs_dir="${backup_dir_hardlinkedblobs}/.blobs"
    backup_dir_path="${backup_dir_hardlinkedblobs}/${prepared_name}"
    hashsum_path="/usr/bin/sha256sum"
    mkdir -p "$backup_dir_hardlinkedblobs"
    mkdir -p "$backup_dir_blobs_dir"
    mkdir -p "$backup_dir_path"
    find "$prepared_dir" -type f -mindepth 1 -exec sh -c '
        relative_path="$(realpath --relative-to="'"$prepared_dir"'" "{}")"
        backup_new_dir="'"$backup_dir_path"'"
        current_new_path="${backup_new_dir}/${relative_path}"
        current_new_dir="$(dirname "$current_new_path")"
        current_hash="$("'"$hashsum_path"'" "{}" | cut -d " " -f 1)"
        current_hash_prefix="$(echo "$current_hash" | cut -b 1-2)"
        current_hash_suffix="$(echo "$current_hash" | cut -b 3-)"
        current_blob_path="'"$backup_dir_blobs_dir"'/${current_hash_prefix}/${current_hash_suffix}"
        current_blob_dir="$(dirname "$current_blob_path")"
        mkdir -p "$current_new_dir"
        [ ! -f "$current_blob_path" ] && { \
            mkdir -p "$current_blob_dir"
            cp "{}" "$current_blob_path"
        }
        ln "$current_blob_path" "$current_new_path"
        ' \;
        find "$backup_dir_blobs_dir" -type f -mindepth 1 -links 1 \
            -exec rm "{}" \;
        find "$backup_dir_blobs_dir" -depth -type d -mindepth 1 -empty \
            -exec rmdir "{}" \;
}

backup_restic() {
    prepared_dir="${1:?prepared_dir}"
    backup_dir_restic="${backup_dir}/restic"
    restic_key_path=/root/.minecraft.key
    command -v restic > /dev/null 2>&1 || return 1
    mkdir -p "$backup_dir_restic"
    [ ! -f "$restic_key_path" ] && {\
        tr -cd 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$restic_key_path"
        chmod 600 "$restic_key_path"
    }
    export RESTIC_REPOSITORY="$backup_dir_restic"
    export RESTIC_PASSWORD_FILE="$restic_key_path"
    restic cat config > /dev/null 2>&1 || { restic --quiet init || return 2; }
    restic --quiet backup "$prepared_dir" --tag minecraft
    restic --quiet forget --tag=minecraft --prune --keep-within 1d --keep-within-hourly 7d --keep-within-weekly 3m --keep-within-monthly 1y --keep-within-yearly 10y 
}

prepare_world_files() {
    world_files="${1:?world_files}"
    # create temp dir e.g., 20240428191654 ensuring it's unique
    world_backup_name=""
    until [ ! -z "$world_backup_name" ] && \
            [ ! -d "${temporary_dir}/$world_backup_name" ]; do
        world_backup_name="$(date '+%Y-%m-%d_%H%M%S_%N')"
    done
    server_base_dir="${server_dir}/worlds"
    temporary_base_dir="${temporary_dir}/${world_backup_name}"
    mkdir -p "$temporary_base_dir"
    # create prepared dir
    mkdir -p "$prepared_dir"
    # iterate over $world_files
    while IFS=':' read -r world_file_path world_file_size 0<&5; do
        [ -z "$world_file_path" ] || [ -z "$world_file_size" ] && continue
        # create world dirs
        current_temporary_file="${temporary_base_dir}/$world_file_path"
        current_temporary_dir="$(dirname "$current_temporary_file")"
        current_server_file="${server_base_dir}/${world_file_path}"
        current_server_dir="$(dirname "$current_server_file")"
        mkdir -p "$current_temporary_dir"
        # copy files to temp dir for processing
        cp "$current_server_file" "${current_temporary_dir}/"
        # truncate files
        truncate "$current_temporary_file" -s "$world_file_size"
        # copy changed files to prepared dir
        current_prepared_file="${prepared_dir}/$world_file_path"
        current_prepared_dir="$(dirname "$current_prepared_file")"
        mkdir -p "$current_prepared_dir"
        cmp -s "$current_prepared_file" "$current_temporary_file" || \
            cp "$current_temporary_file" "$current_prepared_dir"
    done 5<<EOT
$(echo "$world_files" | sed 's/, \{0,1\}/\n/g')
EOT
    # remove irrelevant old dirs/files from prepared dir (sync)
    world_level_name="$(echo "$world_files" | cut -d '/' -f 1)"
    prepared_world_dir="$(realpath "${prepared_dir}/${world_level_name}")"
    temporary_world_dir="$(realpath "${temporary_base_dir}/${world_level_name}")"
    find "$prepared_world_dir" -mindepth 1 -depth -exec sh -c '
        relative_path="$(realpath --relative-to="'"$prepared_world_dir"'" "{}")"
        check_path="'"${temporary_world_dir}"'/${relative_path}"
        [ ! -e "$check_path" ] && { [ -d "{}" ] && rmdir "{}" || rm "{}"; }
        ' \;
    # backup
    mkdir -p "$backup_dir"
    #backup_simple "$world_backup_name" "$prepared_dir"
    #backup_hardlinked "$world_backup_name" "$prepared_dir"
    backup_hardlinkedblobs "$world_backup_name" "$prepared_dir"
    #backup_restic "$prepared_dir"
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

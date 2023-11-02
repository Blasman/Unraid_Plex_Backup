#!/bin/bash

# This script is designed to backup only the essential files that *DO NOT* require the Plex server to be shut down.
# By default, this script will backup the "Media" and "Metadata" folders of Plex to a tar file with a timestamp of the current time.
# You can edit the tar command used in the config below. (ie. specify different folders/files to backup, use compression, etc.)

################################################################################
#                        USER CONFIG (REQUIRED TO EDIT)                        #
################################################################################
BACKUP_DIR="/mnt/user/Backup/Plex Tarball Backups"  # Backup directory.
PLEX_DIR="/mnt/primary/appdata/plex"  # Plex appdata directory.
HOURS_TO_KEEP_BACKUPS_FOR="335"  # Delete backups older than this many hours. [Hours=Days|72=3|96=4|120=5|144=6|168=7|336=14|720=30] (you may also comment out or delete to disable)

################################################################################
#             OPTIONAL ADVANCED USER CONFIG (NOT REQUIRED TO EDIT)             #
################################################################################
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (required for 'STOP_PLEX_DOCKER' variable).
STOP_PLEX_DOCKER=false  # Shutdown Plex docker before backup and restart it after backup. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
RUN_MOVER_BEFORE_BACKUP=false  # Run Unraid's 'mover' BEFORE backing up. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
RUN_MOVER_AFTER_BACKUP=false  # Run Unraid's 'mover' AFTER backing up. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
UNRAID_WEBGUI_START_MSG=true  # Send backup start message to the Unraid Web GUI. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
USE_LOCK_FILE=false  # Set to 'true' (without quotes) to enable use of lock file to prevent overlapping backups. 'rm /tmp/plex_tarball_backup.tmp' to delete lock file if required. (you may also comment out or delete to disable)
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the final tar file. (you may also comment out or delete to disable)
TARFILE_TEXT="Plex Tarball Backup"  # OPTIONALLY customize the text for the backup tar file. As a precaution, the script only deletes old backups that match this pattern.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for the tar filename.
COMPLETE_TAR_FILENAME() { echo "[$(TIMESTAMP)] $TARFILE_TEXT.tar"; }  # OPTIONALLY customize the complete tar file name (adding extension) with the TIMESTAMP and TARFILE_TEXT.
TAR_COMMAND() {  # OPTIONALLY customize the TAR command. Use "$tarfile_complete_path" for the tar file name. This command is ran from within the '/Plex Media Server/' directory.
    tar -cf "$tarfile_complete_path" "Media" "Metadata"
}
# ---------------- ABORT SCRIPT IF ACTIVE PLEX USER SESSIONS ----------------- #
ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS=false  # OPTIONALLY abort the script from running if there are active sessions on the Plex server.
PLEX_SERVER_URL_AND_PORT="http://192.168.1.1:32400"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
PLEX_TOKEN="xxxxxxxxxxxxxxxxxxxx"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
INCLUDE_PAUSED_SESSIONS=false  # Include paused Plex sessions if 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
ALSO_ABORT_ON_FAILED_CONNECTION=false  # Also abort the script if the connection to the Plex server fails when 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
################################################################################
#                              END OF USER CONFIG                              #
################################################################################

# Function that utilizes only built-in bash functions (ie not $date) to append timestamps with milliseconds on all script messages printed to the console.
echo_ts() { printf "[%(%Y_%m_%d)T %(%H:%M:%S)T.${EPOCHREALTIME: -6:3}] $@\\n"; }

# Function to calculate a high precision run timer by subtracting one $EPOCHREALTIME value from another.
run_timer() {
    local run_time=$((${2/./} - ${1/./}))  # Remove decimals in $EPOCHREALTIME values and subtract start time from end time.     #    Examples
    if [[ $run_time -lt 1000000 ]]; then printf -v run_time "%06d" $run_time; echo ".${run_time: -6:4}s";                        #      .1234s
    elif [[ $run_time -lt 10000000 ]]; then echo "${run_time:0:1}.${run_time: -6:3}s";                                           #      1.234s
    elif [[ $run_time -lt 60000000 ]]; then echo "${run_time:0:2}.${run_time: -6:3}s";                                           #     12.345s
    elif [[ $run_time -lt 3600000000 ]]; then echo "$((run_time % 3600000000 / 60000000))m $((run_time % 60000000 / 1000000))s"; #      1m 23s
    elif [[ $run_time -lt 86400000000 ]]; then echo "$((run_time / 3600000000))h $((run_time % 3600000000 / 60000000))m";        #      1h 23m
    else echo "$((run_time / 86400000000))d $((run_time / 3600000000 % 24))h $((run_time % 3600000000 / 60000000))m"; fi         #  1d 23h 45m
}

# Function to get the state of the Plex docker.
get_plex_docker_state() {
    local response=$(docker inspect -f '{{.State.Status}}' "$PLEX_DOCKER_NAME" 2>/dev/null)
    if [[ "$response" =~ ^(running|restarting|started)$ ]]; then echo "running";
    elif [[ "$response" =~ ^(created|exited|paused|stopped)$ ]]; then echo "stopped";
    else echo "error"; fi
}

# Function to abort script if there are active users on the Plex server.
abort_script_run_due_to_active_plex_sessions() {
    local response=$(curl -s --fail --connect-timeout 10 "${PLEX_SERVER_URL_AND_PORT}/status/sessions?X-Plex-Token=${PLEX_TOKEN}")
    if [[ $? -ne 0 ]] && [[ $ALSO_ABORT_ON_FAILED_CONNECTION == true ]]; then
        echo_ts "[ERROR] Could not connect to Plex server. Aborting Plex Tarball Backup."
        exit 1
    elif [[ $response == *'state="playing"'* ]] || ( [[ $INCLUDE_PAUSED_SESSIONS == true ]] && [[ $response == *'state="paused"'* ]] ); then
        echo_ts "Active users on Plex server. Aborting Plex Tarball Backup."
        exit 0
    fi
}

# Function to verify user variables and handle errors.
prepare_backup() {
    if [[ $USE_LOCK_FILE == true ]] && [[ -f "/tmp/plex_tarball_backup.tmp" ]]; then
        echo_ts "[ERROR] Plex Tarball backup is currently active! Lock file can be removed by typing 'rm /tmp/plex_tarball_backup.tmp'. Exiting."
        exit 1
    fi
    if [[ $ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS == true ]]; then abort_script_run_due_to_active_plex_sessions; fi
    if [[ $STOP_PLEX_DOCKER == true ]]; then
        plex_docker_state="$(get_plex_docker_state)"
        if [[ "$plex_docker_state" == "error" ]]; then
            echo_ts "[ERROR] Could not find '$PLEX_DOCKER_NAME' docker. Exiting."
            exit 1
        fi
    fi
    local dir_vars=("BACKUP_DIR" "PLEX_DIR")
    for dir in "${dir_vars[@]}"; do
        local clean_dir="${!dir}"
        clean_dir="${clean_dir%/}"  # Remove trailing slashes.
        eval "$dir=\"$clean_dir\""  # Update the variable with the cleaned path.
        if [ ! -d "$clean_dir" ]; then
            echo_ts "[ERROR] Directory not found: '$clean_dir/'. Exiting."
            exit 1
        fi
    done  # We assume that user has standard Plex appdata folder structure when continuing here.
    plex_pms_dir="$PLEX_DIR/Library/Application Support/Plex Media Server"
    if [[ ! -f "$plex_pms_dir/Plug-in Support/Databases/com.plexapp.plugins.library.db" ]]; then
        echo_ts "[ERROR] COULD NOT FIND Plex database file 'com.plexapp.plugins.library.db'. Please check that '$PLEX_DIR/' is the proper directory for your Plex appdata. Exiting."
        exit 1
    fi
}

# Function to send backup start notification to Unraid's Web GUI.
send_start_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex Tarball Back Up Started."
}

# Function to record the "start time of backup" when 'run_time' is calculated at end of backup.
start_backup() {
    script_start_time=$EPOCHREALTIME
    if [[ $USE_LOCK_FILE == true ]]; then touch "/tmp/plex_tarball_backup.tmp"; fi
    echo_ts "[PLEX TARBALL BACKUP STARTED]"
    if [[ $UNRAID_WEBGUI_START_MSG == true ]]; then send_start_msg_to_unraid_webgui; fi
}

# Function to calculate the age of a tar file in seconds.
get_tarfile_age() {
    local tarfile="$1"
    local current_time=$(date +%s)
    local tarfile_creation_time=$(stat -c %Y "$tarfile")
    local age=$((current_time - tarfile_creation_time))
    echo "$age"
}

# Function to delete old backup tar files.
delete_old_backups() {
    local cutoff_age=$(($HOURS_TO_KEEP_BACKUPS_FOR * 3600))
    for tarfile in "$BACKUP_DIR"/*"$TARFILE_TEXT"*; do
        if [ -f "$tarfile" ]; then
            local tarfile_age=$(get_tarfile_age "$tarfile")
            if [ "$tarfile_age" -gt "$cutoff_age" ]; then
                rm -rf "$tarfile"
                echo_ts "Deleted old Plex Tarball backup: $tarfile"
            fi
        fi
    done
}

# Function to run Unraid's 'mover'.
run_mover() {
    local mover_status=""
    mover_status=$(mover status)
    if [[ $mover_status == *"mover: not running"* ]]; then
        echo_ts "Started 'mover'..."
        mover start >/dev/null
        echo_ts "Finished 'mover'."
    else
        echo_ts "Skipping 'mover' because it is currently active."
    fi
}

# Function to stop Plex docker.
stop_plex() {
    if [[ "$plex_docker_state" == "running" ]]; then
        echo_ts "Stopping Plex docker..."
        docker stop "$PLEX_DOCKER_NAME" >/dev/null
        echo_ts "Plex docker stopped."
    else
        echo_ts "Plex docker already stopped. Skipping docker stop."
    fi
}

# Function to set permissions on the tar file.
set_permissions() {
  # echo_ts "Running 'chmod $PERMISSIONS' on file..."
    chmod $PERMISSIONS "$tarfile_complete_path"
  # echo_ts "Successfully set permissions on file."
}

# Function to create the tar file.
create_tarfile() {
    local create_tarfile_start_time=$EPOCHREALTIME
    cd "$plex_pms_dir"  # Navigate to $plex_pms_dir working directory to shorten the tar command.
    tarfile_complete_path="$BACKUP_DIR/$(COMPLETE_TAR_FILENAME)"
    echo_ts "Creating file: '$tarfile_complete_path'"
    TAR_COMMAND
    tarfile_filesize=$(du -hs "$tarfile_complete_path" | awk '{print $1}')
    echo_ts "Created $tarfile_filesize file in $(run_timer $create_tarfile_start_time $EPOCHREALTIME)."
    if [[ $PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then set_permissions; fi
}

# Function to start Plex docker.
start_plex() {
    plex_docker_state="$(get_plex_docker_state)"
    if [[ "$plex_docker_state" == "stopped" ]]; then
        echo_ts "Starting Plex docker..."
        docker start "$PLEX_DOCKER_NAME" >/dev/null
        echo_ts "Plex docker started."
    else
        echo_ts "Plex docker already started. Skipping docker start."
    fi
}

# Function to send backup success notification to Unraid's Web GUI.
send_success_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex Tarball Back Up Complete." -d "Run time: $run_time. Filesize: $tarfile_filesize."
}

# Function to print backup completed message to console with the 'run_time' variable.
complete_backup() {
    run_time=$(run_timer $script_start_time $EPOCHREALTIME)
    if [[ $USE_LOCK_FILE == true ]]; then rm "/tmp/plex_tarball_backup.tmp"; fi
    echo_ts "[PLEX TARBALL BACKUP COMPLETE] Run Time: $run_time. Filesize: $tarfile_filesize."
    if [[ $UNRAID_WEBGUI_SUCCESS_MSG == true ]]; then send_success_msg_to_unraid_webgui; fi
}

################################################################################
#                            BEGIN PROCESSING HERE                             #
################################################################################

# Verify correctly set user variables and other error handling.
prepare_backup

# Delete old backup tar files first to create more usable storage space. Move this function lower in processing if desired.
if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+$ ]]; then delete_old_backups; fi

# Run mover before Backup.
if [[ $RUN_MOVER_BEFORE_BACKUP == true ]]; then run_mover; fi

# Print backup start message to console. This is consided the "start of the backup" when 'run_time' is calculated.
start_backup

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER == true ]]; then stop_plex; fi

# Create the tar file.
create_tarfile

# Start Plex Docker.
if [[ $STOP_PLEX_DOCKER == true ]]; then start_plex; fi

# Print backup completed message to console with the 'run_time' for the backup.
complete_backup

# Run mover after Backup.
if [[ $RUN_MOVER_AFTER_BACKUP == true ]]; then run_mover; fi

# Exit with success.
exit 0

#!/bin/bash

# This script is designed to backup only the essential files that *DO NOT* require the Plex server to be shut down.
# By default, this script will backup the "Media" and "Metadata" folders of Plex to a tar file with a timestamp of the current time.
# You can edit the tar command used in the config below. (ie. specify different folders/files to backup, use compression, etc.)

################################################################################
# ---------------------- USER CONFIG (REQUIRED TO EDIT) ---------------------- #
################################################################################
PLEX_DIR="/mnt/primary/appdata/plex/Library/Application Support/Plex Media Server"  # "Plex Media Server" folder location *within* the plex appdata folder.
BACKUP_DIR="/mnt/user/Backup/Plex Metadata Backups"  # Backup folder location.
HOURS_TO_KEEP_BACKUPS_FOR="324"  # Delete backups older than this many hours. Comment out or delete to disable.
STOP_PLEX_DOCKER=false  # Shutdown Plex docker before backup and restart it after backup. Set to "true" (without quotes) to use. Comment out or delete to disable.
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (needed for 'STOP_PLEX_DOCKER' variable).
################################################################################
# --------------- OPTIONAL USER CONFIG (NOT REQUIRED TO EDIT) ---------------- #
################################################################################
RUN_MOVER_BEFORE_BACKUP=false  # Run Unraid's 'mover' BEFORE backing up. Set to "true" (without quotes) to use. Comment out or delete to disable.
RUN_MOVER_AFTER_BACKUP=false  # Run Unraid's 'mover' AFTER backing up. Set to "true" (without quotes) to use. Comment out or delete to disable.
UNRAID_WEBGUI_START_MSG=true  # Send backup start message to the Unraid Web GUI. Set to "true" (without quotes) to use. Comment out or delete to disable.
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to "true" (without quotes) to use. Comment out or delete to disable.
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the final tar file. Comment out or delete to disable.
TARFILE_TEXT="Plex Metadata Backup"  # OPTIONALLY customize the text for the backup tar file. As a precaution, the script only deletes old backups that match this pattern.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for the tar filename.
COMPLETE_TAR_FILENAME() { echo "[$(TIMESTAMP)] $TARFILE_TEXT.tar"; }  # OPTIONALLY customize the complete tar file name (adding extension) with the TIMESTAMP and TARFILE_TEXT.
TAR_COMMAND() {  # OPTIONALLY customize the TAR command. Use "$tarfile_complete_path" for the tar file name. This command is ran from within the $PLEX_DIR directory.
    tar -cf "$tarfile_complete_path" "Media" "Metadata"
}
ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS=false  # OPTIONALLY abort the script from running if there are active sessions on the Plex server.
PLEX_SERVER_URL_AND_PORT="http://192.168.1.1:32400"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
PLEX_TOKEN="xxxxxxxxxxxxxxxxxxxx"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
INCLUDE_PAUSED_SESSIONS=false  # Include paused Plex sessions if 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
ALSO_ABORT_ON_FAILED_CONNECTION=false  # Also abort the script if the connection to the Plex server fails when 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
################################################################################
# ---------------------------- END OF USER CONFIG ---------------------------- #
################################################################################

# Function to append timestamps with milliseconds on all script messages printed to the console.
echo_ts() { local ms=${EPOCHREALTIME#*.}; printf "[%(%Y_%m_%d)T %(%H:%M:%S)T.${ms::3}] $@\\n"; }

# Function to calculate a 'run timer' with precision accuracy as quickly as possible by subtracting one $EPOCHREALTIME value from another.
run_timer() {  # If result is < 10 seconds, then 4 digits after decimal. Else If result is < 60 seconds, then 3 digits after decimal.
    local start_time="$1"; local end_time="$2"; local run_time=$((${end_time/./} - ${start_time/./}))
    if [[ $run_time -lt 10000000 ]]; then printf -v run_time "%07d" $run_time; echo "${run_time:0:1}.${run_time: -6:4}s";
    elif [[ $run_time -lt 60000000 ]]; then printf -v run_time "%08d" $run_time; echo "${run_time:0:2}.${run_time: -6:3}s";
    elif [[ $run_time -lt 3600000000 ]]; then echo "$((run_time % 3600000000 / 60000000))m ${run_time: -8:2}s";
    else echo "$((run_time / 3600000000))h $((run_time % 3600000000 / 60000000))m ${run_time: -8:2}s"; fi
}  # Example Usage: echo "Completed in $(run_timer $start_time $EPOCHREALTIME)."

# Function to abort script if there are active users on the Plex server.
abort_script_run_due_to_active_plex_sessions() {
    response=$(curl -s --fail --connect-timeout 10 "${PLEX_SERVER_URL_AND_PORT}/status/sessions?X-Plex-Token=${PLEX_TOKEN}")
    if [[ $? -ne 0 ]] && [[ $ALSO_ABORT_ON_FAILED_CONNECTION = true ]]; then
        echo_ts "[ERROR] Could not connect to Plex server. Aborting Plex Metadata Backup."
        exit 1
    elif [[ $response == *'state="playing"'* ]] || ( [[ $INCLUDE_PAUSED_SESSIONS = true ]] && [[ $response == *'state="paused"'* ]] ); then
        echo_ts "Active users on Plex server. Aborting Plex Metadata Backup."
        exit 0
    fi
}

# Function to verify that "$BACKUP_DIR" and "$PLEX_DIR" are valid paths.
verify_valid_path_variables() {
    local dir_vars=("BACKUP_DIR" "PLEX_DIR")
    for dir in "${dir_vars[@]}"; do
        local clean_dir="${!dir}"
        clean_dir="${clean_dir%/}"  # Remove trailing slashes
        eval "$dir=\"$clean_dir\""  # Update the variable with the cleaned path
        if [ ! -d "$clean_dir" ]; then
            echo "[ERROR] Directory not found: $clean_dir"
            exit 1
        fi
    done
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
                echo_ts "Deleted old backup: $tarfile"
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

# Function to record the "start time of backup" when 'run_time' is calculated at end of backup.
start_backup() {
    script_start_time=$EPOCHREALTIME
    echo_ts "[PLEX TARBALL BACKUP STARTED]"
}

# Function to send backup start notification to Unraid's Web GUI.
send_start_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex Tarball Back Up Started."
}

# Function to stop Plex docker.
stop_plex() {
    echo_ts "Stopping Plex Server..."
    docker stop "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server stopped."
}

# Function to create the tar file.
create_tarfile() {
    local create_tarfile_start_time=$EPOCHREALTIME
    cd "$PLEX_DIR"  # Navigate to $PLEX_DIR working directory to shorten the tar command.
    tarfile_complete_path="$BACKUP_DIR/$(COMPLETE_TAR_FILENAME)"
    echo_ts "Creating file: '$tarfile_complete_path'"
    TAR_COMMAND
    tarfile_filesize=$(du -hs "$tarfile_complete_path" | awk '{print $1}')
    echo_ts "Created $tarfile_filesize file in $(run_timer $create_tarfile_start_time $EPOCHREALTIME)."
}

# Function to start Plex docker.
start_plex() {
    echo_ts "Starting Plex Server..."
    docker start "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server started."
}

# Function to set permissions on the tar file.
set_permissions() {
    echo_ts "Running 'chmod $PERMISSIONS' on file..."
    chmod $PERMISSIONS "$tarfile_complete_path"
    echo_ts "Successfully set permissions on file."
}

# Function to print backup completed message to console with the 'run_time' variable.
complete_backup() {
    run_time=$(run_timer $script_start_time $EPOCHREALTIME)
    echo_ts "[PLEX TARBALL BACKUP COMPLETE] Run Time: $run_time. Filesize: $tarfile_filesize."
}

# Function to send backup success notification to Unraid's Web GUI.
send_success_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex Tarball Back Up Complete." -d "Run time: $run_time. Filesize: $tarfile_filesize."
}

###############################################
############# BACKUP BEGINS HERE ##############
###############################################

# Abort script if there are active users on the Plex server.
if [[ $ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS = true ]]; then abort_script_run_due_to_active_plex_sessions; fi

# Verify that $BACKUP_DIR and $PLEX_DIR are valid paths.
verify_valid_path_variables

# Delete old backup tar files first to create more usable storage space.
if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+(\.[0-9]+)?$ ]]; then delete_old_backups; fi

# Run mover before Backup.
if [[ $RUN_MOVER_BEFORE_BACKUP = true ]]; then run_mover; fi

# Print backup start message to console. This is consided the "start of the backup" when 'run_time' is calculated.
start_backup

# Send backup started notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_START_MSG = true ]]; then send_start_msg_to_unraid_webgui; fi

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER = true ]]; then stop_plex; fi

# Create the tar file.
create_tarfile

# Start Plex Docker before doing anything else.
if [[ $STOP_PLEX_DOCKER = true ]]; then start_plex; fi

# Set permissions for the tar file.
if [[ $PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then set_permissions; fi

# Print backup completed message to console with the 'run_time' for the backup.
complete_backup

# Send backup completed notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_SUCCESS_MSG = true ]]; then send_success_msg_to_unraid_webgui; fi

# Run mover after Backup.
if [[ $RUN_MOVER_AFTER_BACKUP = true ]]; then run_mover; fi

# Exit with success.
exit 0

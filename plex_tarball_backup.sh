#!/bin/bash

# This script is designed to backup only the essential files that *DO NOT* require the Plex server to be shut down.
# By default, this script will backup the "Media" and "Metadata" folders of Plex to a tar file with a timestamp of the current time.
# You can edit the tar command used in the config below. (ie. specify different folders/files to backup, use compression, etc.)

#########################################################
################### USER CONFIG BELOW ###################
#########################################################

PLEX_DIR="/mnt/primary/appdata/plex/Library/Application Support/Plex Media Server"  # "Plex Media Server" folder location *within* the plex appdata folder.
BACKUP_DIR="/mnt/user/Backup/Plex Metadata Backups"  # Backup folder location.
HOURS_TO_KEEP_BACKUPS_FOR="324"  # Delete backups older than this many hours. Comment out or delete to disable.
STOP_PLEX_DOCKER=false  # Shutdown Plex docker before backup and restart it after backup. Set to "true" (without quotes) to use. Comment out or delete to disable.
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (needed for 'STOP_PLEX_DOCKER' variable).
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the final tar file. Comment out or delete to disable.
RUN_MOVER_BEFORE_BACKUP=true  # Run Unraid's 'mover' BEFORE backing up. Set to "true" (without quotes) to use. Comment out or delete to disable.
RUN_MOVER_AFTER_BACKUP=true  # Run Unraid's 'mover' AFTER backing up. Set to "true" (without quotes) to use. Comment out or delete to disable.
UNRAID_WEBGUI_START_MSG=true  # Send backup start message to the Unraid Web GUI. Set to "true" (without quotes) to use. Comment out or delete to disable.
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to "true" (without quotes) to use. Comment out or delete to disable.
#----------- OPTIONAL ADVANCED CONFIG BELOW ------------#
TARFILE_TEXT="Plex Metadata Backup"  # OPTIONALLY customize the text for the backup tar file. As a precaution, the script only deletes old backups that match this pattern.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for the tar filename.
COMPLETE_TARFILE_NAME() { echo "[$(TIMESTAMP)] $TARFILE_TEXT.tar"; }  # OPTIONALLY customize the complete tar file name (adding extension) with the TIMESTAMP and TARFILE_TEXT.
TAR_COMMAND() {  # OPTIONALLY customize the TAR command. Use "$TAR_FILE" for the tar file name. This command is ran from within the $PLEX_DIR directory.
    tar -cf "$TAR_FILE" "Media" "Metadata"
}
ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS=false  # OPTIONALLY abort the script from running if there are active sessions on the Plex server.
PLEX_SERVER_URL_AND_PORT="http://192.168.1.1:32400"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
PLEX_TOKEN="xxxxxxxxxxxxxxxxxxxx"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
INCLUDE_PAUSED_SESSIONS=false  # Include paused Plex sessions if 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
ALSO_ABORT_ON_FAILED_CONNECTION=false  # Also abort the script if the connection to the Plex server fails when 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.

#########################################################
################## END OF USER CONFIG ###################
#########################################################

# Function to append timestamps on all script messages printed to the console.
echo_ts() { local ms=${EPOCHREALTIME#*.}; printf "[%(%Y_%m_%d)T %(%H:%M:%S)T.${ms:0:3}] $@\\n"; }

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

# Function to start the script. Print start message and get starting time.
start_script() {
    script_start_time=$EPOCHREALTIME
    echo_ts "[PLEX TARBALL BACKUP STARTED]"
}

# Function to send backup start notification to Unraid's Web GUI.
send_start_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex Tar Back Up Started."
}

# Function to stop Plex docker.
stop_plex() {
    echo_ts "Stopping Plex Server..."
    docker stop "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server stopped."
}

# Function to create the tar file.
create_tar_file() {
    # Navigate to $PLEX_DIR working directory to shorten the tar command.
    cd "$PLEX_DIR"
    # Create tar file name with the custom timestamp.
    TAR_FILE="$BACKUP_DIR/$(COMPLETE_TARFILE_NAME)"
    echo_ts "Creating tar file..."
    # Run the tar command.
    TAR_COMMAND
    echo_ts "Tar file created."
}

# Function to start Plex docker.
start_plex() {
    echo_ts "Starting Plex Server..."
    docker start "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server started."
}

# Function to set permissions on the tar file.
set_permissions() {
    echo_ts "Running 'chmod $PERMISSIONS' on tar file..."
    chmod $PERMISSIONS "$TAR_FILE"
    echo_ts "Successfully set permissions on tar file."
}

# Function to create a 'run_time' variable with a milliseconds value from two separate $EPOCHREALTIME style values.
millisecond_run_timer() {
    local start_time="$1" local end_time="$2"
    local start_time_integer=${start_time/./}
    local end_time_integer=${end_time/./}
    local run_time=$((end_time_integer - start_time_integer))
    local before_decimal="${run_time::-6}"  # Get value before decimal
    local after_decimal="${run_time%???}"  # Get value after decimal
    local trimmed_after_decimal="${after_decimal: -3}"
    local hours=$((before_decimal / 3600))  # Calculate hours
    local minutes=$((before_decimal % 3600 / 60))  # Calculate minutes
    local seconds=$((before_decimal % 60))  # Calculate seconds
    local formatted_before_decimal="" local formatted_seconds=""
    if [ $hours -gt 0 ]; then formatted_before_decimal="${hours}h "; fi
    if [ $minutes -gt 0 ]; then formatted_before_decimal="${formatted_before_decimal}${minutes}m "; fi
    if [ $seconds -gt 0 ]; then formatted_seconds=$seconds; else formatted_seconds="0"; fi
    formatted_before_decimal="${formatted_before_decimal}${formatted_seconds}"
    run_time="$formatted_before_decimal."$trimmed_after_decimal"s"
    echo "$run_time"
}

# Function to end the script. Print backup completed message with runtime.
end_script() {
    run_time=$(millisecond_run_timer $script_start_time $EPOCHREALTIME)
    echo_ts "[PLEX TARBALL BACKUP COMPLETE] Run Time: $run_time."
}

# Function to send backup success notification to Unraid's Web GUI.
send_success_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex Tarball Back Up Complete." -d "Run time: $run_time."
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

# Start 'main' backup script processing. Print console message and get start time.
start_script

# Send backup started notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_START_MSG = true ]]; then send_start_msg_to_unraid_webgui; fi

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER = true ]]; then stop_plex; fi

# Create the tar file.
create_tar_file

# Start Plex Docker before doing anything else.
if [[ $STOP_PLEX_DOCKER = true ]]; then start_plex; fi

# Set permissions for the tar file.
if [[ $PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then set_permissions; fi

# Backup completed message with runtime.
end_script

# Send backup completed notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_SUCCESS_MSG = true ]]; then send_success_msg_to_unraid_webgui; fi

# Run mover after Backup.
if [[ $RUN_MOVER_AFTER_BACKUP = true ]]; then run_mover; fi

# Exit with success.
exit 0

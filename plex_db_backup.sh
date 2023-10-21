#!/bin/bash

# This script is designed to backup only the essential files that *DO* require the Plex server to be shut down.
# By default, these are the two DB files 'com.plexapp.plugins.library.db' 'com.plexapp.plugins.library.blobs.db' and 'Preferences.xml'.
# The files are placed in their own sub-directory (with a timestamp of the current time) within the specified backup directory.
# You can edit the default copy function in the config below to specify different folders/files to backup.

#########################################################
################### USER CONFIG BELOW ###################
#########################################################

PLEX_DIR="/mnt/primary/appdata/plex/Library/Application Support/Plex Media Server"  # "Plex Media Server" folder location *within* the plex appdata folder.
BACKUP_DIR="/mnt/user/Backup/Plex DB Backups"  # Backup folder location.
HOURS_TO_KEEP_BACKUPS_FOR="95"  # Delete backups older than this many hours. Comment out or delete to disable deletion of old backups.
STOP_PLEX_DOCKER=true  # Shutdown Plex docker before backup and restart it after backup. Set to "true" (without quotes) to use. Comment out or delete to disable.
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (needed for 'STOP_PLEX_DOCKER' variable).
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the backup sub-directory and files. Comment out or delete to disable.
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to "true" (without quotes) to use. Comment out or delete to disable.
#----------- OPTIONAL ADVANCED CONFIG BELOW ------------#
SUBDIR_TEXT="Plex DB Backup"  # OPTIONALLY customize the text for the backup sub-directory name. As a precaution, the script only deletes old backups that match this pattern.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for backup sub-directory name.
COMPLETE_SUBDIR_NAME() { echo "[$(TIMESTAMP)] $SUBDIR_TEXT"; }  # OPTIONALLY customize the complete backup sub-directory name with the TIMESTAMP and SUBDIR_TEXT.
BACKUP_COMMAND() {  # OPTIONALLY customize the function that copies the files.
    cp "$PLEX_DIR/Preferences.xml" "$BACKUP_PATH/Preferences.xml"
    cp "$PLEX_DIR/Plug-in Support/Databases/com.plexapp.plugins.library.db" "$BACKUP_PATH/com.plexapp.plugins.library.db"
    cp "$PLEX_DIR/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db" "$BACKUP_PATH/com.plexapp.plugins.library.blobs.db"
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
        echo_ts "[ERROR] Could not connect to Plex server. Aborting Plex DB Backup."
        exit 1
    elif [[ $response == *'state="playing"'* ]] || ( [[ $INCLUDE_PAUSED_SESSIONS = true ]] && [[ $response == *'state="paused"'* ]] ); then
        echo_ts "Active users on Plex server. Aborting Plex DB Backup."
        exit 0
    fi
}

# Function to verify that "$BACKUP_DIR" and "$PLEX_DIR" are valid paths.
verify_valid_path_variables() {
    local dirs=("$BACKUP_DIR" "$PLEX_DIR")
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "[ERROR] Directory not found: $dir"
            exit 1
        fi
    done
}

# Function to stop Plex docker.
stop_plex() {
    echo_ts "Stopping Plex Server..."
    docker stop "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server stopped."
}

# Function to back up the files.
backup_files() {
    echo_ts "Copying Files..."
    # Create sub-directory name with the custom timestamp.
    BACKUP_PATH="$BACKUP_DIR/$(COMPLETE_SUBDIR_NAME)"
    # Create the backup sub-directory.
    mkdir -p "$BACKUP_PATH"
    # Run the backup command.
    BACKUP_COMMAND
    echo_ts "Files copied."
}

# Function to start Plex docker.
start_plex() {
    echo_ts "Starting Plex Server..."
    docker start "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server started."
}

# Function to set permissions on the backup sub-directory.
set_permissions() {
    echo_ts "Running 'chmod -R $PERMISSIONS' on backup sub-directory..."
    chmod -R $PERMISSIONS "$BACKUP_PATH"
    echo_ts "Successfully set permissions on backup sub-directory."
}

# Function to calculate the age of a directory in seconds.
get_directory_age() {
    local dir="$1"
    local current_time=$(date +%s)
    local dir_creation_time=$(stat -c %Y "$dir")
    local age=$((current_time - dir_creation_time))
    echo "$age"
}

# Function to delete old backup directories. Be careful if editing.
delete_old_backups() {
    local cutoff_age=$(($HOURS_TO_KEEP_BACKUPS_FOR * 3600))
    for dir in "$BACKUP_DIR"/*"$SUBDIR_TEXT"*; do
        if [ -d "$dir" ]; then
            local dir_age=$(get_directory_age "$dir")
            if [ "$dir_age" -gt "$cutoff_age" ]; then
                rm -rf "$dir"
                echo_ts "Deleted old Plex Backup: '$(basename "$dir")'"
            fi
        fi
    done
}

# Function to send backup success notification to Unraid's Web GUI.
send_success_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex DB Back Up Complete." -d "Successfully backed up files to '$BACKUP_PATH'."
}

###############################################
############# BACKUP BEGINS HERE ##############
###############################################

# Abort script if there are active users on the Plex server.
if [[ $ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS = true ]]; then abort_script_run_due_to_active_plex_sessions; fi

# Verify that $BACKUP_DIR and $PLEX_DIR are valid paths.
verify_valid_path_variables

# Start backup message.
echo_ts "[PLEX BACKUP STARTED]"

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER = true ]]; then stop_plex; fi

# Copy the files from Plex to the backup sub-directory.
backup_files

# Start Plex Docker before doing anything else.
if [[ $STOP_PLEX_DOCKER = true ]]; then start_plex; fi

# Set permissions for the backup directory and its contents.
if [[ $PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then set_permissions; fi

# Delete old backups.
if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+(\.[0-9]+)?$ ]]; then delete_old_backups; fi

# Backup completed message.
echo_ts "[PLEX BACKUP COMPLETE] Backed created at '$BACKUP_PATH'."

# Send backup completed notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_SUCCESS_MSG = true ]]; then send_success_msg_to_unraid_webgui; fi

# Exit with success.
exit 0

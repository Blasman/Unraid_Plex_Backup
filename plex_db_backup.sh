#!/bin/bash

# This script is designed to backup only the essential files that *DO* require the Plex server to be shut down.
# By default, these are the two DB files 'com.plexapp.plugins.library.db' 'com.plexapp.plugins.library.blobs.db' and 'Preferences.xml'.
# The files are placed in their own sub-folder (with a timestamp of the current time) within the specified backup directory.
# You can edit the default copy function in the config below to specify different folders/files to backup.

#########################################################
################### USER CONFIG BELOW ###################
#########################################################

PLEX_DIR="/mnt/primary/appdata/plex/Library/Application Support/Plex Media Server"  # "Plex Media Server" folder location *within* the plex appdata folder.
BACKUP_DIR="/mnt/user/Backup/Plex DB Backups"  # Backup folder location.
SUBDIR_NAME="Plex DB Backup"  # Name of the backup folder sub-directory created for each backup. Comes after the timestamp in the directory name.
HOURS_TO_KEEP_BACKUPS_FOR="95"  # Delete backups older than this many hours. Set to any other value or comment out/delete to disable.
STOP_PLEX_DOCKER=true  # Shutdown Plex docker before backup and restart it after backup. Set to "true" (without quotes) to use. Set to any other value or comment out/delete to disable.
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (needed for 'STOP_PLEX_DOCKER' variable).
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the final tar file. Set to any other value or comment out/delete to disable.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # Optionally customize TIMESTAMP for sub-directory name.
BACKUP_COMMAND() {  # Optionally customize the function that copies the files.
    cp "$PLEX_DIR/Preferences.xml" "$BACKUP_SUBDIR/Preferences.xml"
    cp "$PLEX_DIR/Plug-in Support/Databases/com.plexapp.plugins.library.db" "$BACKUP_SUBDIR/com.plexapp.plugins.library.db"
    cp "$PLEX_DIR/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db" "$BACKUP_SUBDIR/com.plexapp.plugins.library.blobs.db"
}

#########################################################
################## END OF USER CONFIG ###################
#########################################################

# Function to append timestamps on all script messages printed to the console.
echo_ts() { local ms=${EPOCHREALTIME#*.}; printf "[%(%Y_%m_%d)T %(%H:%M:%S)T.${ms:0:3}] $@\\n"; }

# Function to check the existence of a directory.
check_directory_existence() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo_ts "[ERROR] Directory not found: $dir"
        exit 1
    fi
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
    chmod -R $PERMISSIONS "$BACKUP_SUBDIR"
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
    for dir in "$BACKUP_DIR"/*; do
        if [ -d "$dir" ]; then
            local dir_age=$(get_directory_age "$dir")
            if [ "$dir_age" -gt "$cutoff_age" ]; then
                rm -rf "$dir"
                echo_ts "Deleted old Plex Backup: '$(basename "$dir")'"
            fi
        fi
    done
}

###############################################
############# BACKUP BEGINS HERE ##############
###############################################

# Check if BACKUP_DIR and PLEX_DIR exist. Do not remove from script.
check_directory_existence "$BACKUP_DIR"
check_directory_existence "$PLEX_DIR"

# Start backup message.
echo_ts "[PLEX BACKUP STARTED]"

# Custom sub-directory name with the custom timestamp.
BACKUP_SUBDIR="$BACKUP_DIR/[$(TIMESTAMP)] $SUBDIR_NAME"

# Create the backup sub-directory.
mkdir -p "$BACKUP_SUBDIR"

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
echo_ts "[PLEX BACKUP COMPLETE] Backed created at '$BACKUP_SUBDIR'."

# Exit with success.
exit 0

#!/bin/bash

# This script is designed to backup only the essential files that *DO NOT* require the Plex server to be shut down.
# By default, this script will backup the "Media" and "Metadata" folders of Plex to a tar file with a timestamp of the current time.
# You can edit the tar command used in the config below. (ie. specify different folders/files to backup, use compression, etc.)

#########################################################
################### USER CONFIG BELOW ###################
#########################################################

PLEX_DIR="/mnt/primary/appdata/plex/Library/Application Support/Plex Media Server"  # "Plex Media Server" folder location *within* the plex appdata folder.
BACKUP_DIR="/mnt/user/Backup/Plex Metadata Backups"  # Backup folder location.
BACKUP_FILENAME="Plex Metadata Backup"  # Filename of .tar file without the .tar extension. Comes after the timestamp in the filename.
HOURS_TO_KEEP_BACKUPS_FOR="324"  # Delete backups older than this many hours. Set to any other value or comment out/delete to disable.
STOP_PLEX_DOCKER=false  # Shutdown Plex docker before backup and restart it after backup. Set to "true" (without quotes) to use. Set to any other value or comment out/delete to disable.
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (needed for 'STOP_PLEX_DOCKER' variable).
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the final tar file. Set to any other value or comment out/delete to disable.
RUN_MOVER_BEFORE_BACKUP=true  # Run Unraid's 'mover' BEFORE backing up. Set to "true" (without quotes) to use. Set to any other value or comment out/delete to disable.
RUN_MOVER_AFTER_BACKUP=true  # Run Unraid's 'mover' AFTER backing up. Set to "true" (without quotes) to use. Set to any other value or comment out/delete to disable.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # Optionally customize TIMESTAMP for the tar filename.
TAR_COMMAND() {  # Optionally customize the TAR command. Use "$TAR_FILE" for the tar file name. This command is ran from within the $PLEX_DIR directory.
    tar -cf "$TAR_FILE" "Media" "Metadata"
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
    for tarfile in "$BACKUP_DIR"/*.tar; do
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

# Function to stop Plex docker.
stop_plex() {
    echo_ts "Stopping Plex Server..."
    docker stop "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex Server stopped."
}

# Function to create the tar file.
create_tar_file() {
    echo_ts "Creating tar file..." 
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

###############################################
############# BACKUP BEGINS HERE ##############
###############################################

# Check if BACKUP_DIR and PLEX_DIR exist.
check_directory_existence "$BACKUP_DIR"
check_directory_existence "$PLEX_DIR"

# Delete old backup tar files first to create more usable storage space.
if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+(\.[0-9]+)?$ ]]; then delete_old_backups; fi

# Run mover before Backup.
if [[ $RUN_MOVER_BEFORE_BACKUP = true ]]; then run_mover; fi

# Start backup message.
echo_ts "[PLEX TARBALL BACKUP STARTED]"

# Navigate to $PLEX_DIR working direcotry.
cd "$PLEX_DIR"

# Determine full path and filename for tar backup file.
TAR_FILE="$BACKUP_DIR/[$(TIMESTAMP)] $BACKUP_FILENAME.tar"

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER = true ]]; then stop_plex; fi

# Create the tar file.
create_tar_file

# Start Plex Docker before doing anything else.
if [[ $STOP_PLEX_DOCKER = true ]]; then start_plex; fi

# Set permissions for the tar file.
if [[ $PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then set_permissions; fi

# Backup completed message.
echo_ts "[PLEX TARBALL BACKUP COMPLETE] Backed created at '$TAR_FILE'."

# Run mover after Backup.
if [[ $RUN_MOVER_AFTER_BACKUP = true ]]; then run_mover; fi

# Exit with success.
exit 0

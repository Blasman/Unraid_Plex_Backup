#!/bin/bash

# This script is designed to backup only the essential files that *DO* require the Plex server to be shut down.
# By default, these are the two DB files 'com.plexapp.plugins.library.db' 'com.plexapp.plugins.library.blobs.db' and 'Preferences.xml'.
# The files are placed in their own sub-directory (with a timestamp of the current time) within the specified backup directory.
# You can edit the default copy function in the config below to specify different folders/files to backup.

################################################################################
#                        USER CONFIG (REQUIRED TO EDIT)                        #
################################################################################
PLEX_DIR="/mnt/primary/appdata/plex/Library/Application Support/Plex Media Server"  # FULL PATH to /Plex Media Server/ folder *within* the plex appdata folder.
BACKUP_DIR="/mnt/user/Backup/Plex DB Backups"  # Backup folder location.
HOURS_TO_KEEP_BACKUPS_FOR="95"  # Delete backups older than this many hours. Hrs to Days: [48=2|72=3|96=4|120=5|144=6|168=7|336=14|720=30] (you may also comment out or delete to disable)
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (needed for 'STOP_PLEX_DOCKER' variable).
# ---------------------- PLEX TARBALL BACK UP SETTINGS ----------------------- #  This is an alternative to setting individual cron jobs for both backup scripts.
RUN_TARBALL_BACKUP_UPON_COMPLETION=false  # Set to 'true' (without quotes) to run the Tarball backup script in Unraid's user-scripts immediately after this script. 
DAYS_TO_RUN_TARBALL_SCRIPT_ON="1 4"  # Days of the week to trigger the Tarball backup script on (separated by spaces). Same as would be in cron (most systems: 0 = Sunday, 6 = Saturday).
NAME_OF_TARBALL_SCRIPT="Plex Metadata Backup"  # Name of the Tarball backup script in Unraid's user-scripts. (click on cogwheel, will be BASENAME dir. ie last dir of: '/boot/config/plugins/user.scripts/scripts/Plex Metadata Backup')
################################################################################
#                 OPTIONAL USER CONFIG (NOT REQUIRED TO EDIT)                  #
################################################################################
STOP_PLEX_DOCKER=true  # Shutdown Plex docker before backup and restart it after backup. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
UNRAID_WEBGUI_START_MSG=true  # Send backup start message to the Unraid Web GUI. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the backup sub-directory and files. (you may also comment out or delete to disable)
SUBDIR_TEXT="Plex DB Backup"  # OPTIONALLY customize the text for the backup sub-directory name. As a precaution, the script only deletes old backups that match this pattern.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for backup sub-directory name.
COMPLETE_SUBDIR_NAME() { echo "[$(TIMESTAMP)] $SUBDIR_TEXT"; }  # OPTIONALLY customize the complete backup sub-directory name with the TIMESTAMP and SUBDIR_TEXT.
BACKUP_COMMAND() {  # OPTIONALLY customize the function that copies the files. Use "$backup_path" to specify the full backup path.
    cp "$PLEX_DIR/Preferences.xml" "$backup_path/Preferences.xml"
    cp "$PLEX_DIR/Plug-in Support/Databases/com.plexapp.plugins.library.db" "$backup_path/com.plexapp.plugins.library.db"
    cp "$PLEX_DIR/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db" "$backup_path/com.plexapp.plugins.library.blobs.db"
}
# ---------------- ABORT SCRIPT IF ACTIVE PLEX USER SESSIONS ----------------- #
ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS=false  # OPTIONALLY abort the script from running if there are active sessions on the Plex server.
PLEX_SERVER_URL_AND_PORT="http://192.168.1.1:32400"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
PLEX_TOKEN="xxxxxxxxxxxxxxxxxxxx"  # ONLY REQUIRED if using 'ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS' is set to 'true'.
INCLUDE_PAUSED_SESSIONS=false  # Include paused Plex sessions as active users.
ALSO_ABORT_ON_FAILED_CONNECTION=false  # Also abort the script if the connection to the Plex server fails.
################################################################################
#                              END OF USER CONFIG                              #
################################################################################

# Function that utilizes only built-in bash functions (ie not $date) to append timestamps with milliseconds on all script messages printed to the console.
echo_ts() { printf "[%(%Y_%m_%d)T %(%H:%M:%S)T.${EPOCHREALTIME: -6:3}] $@\\n"; }

# Function to calculate a high precision 'run timer' as quickly as possible by subtracting one $EPOCHREALTIME value from another.
run_timer() {  # If result is < 10 seconds, then 4 digits after decimal. Else If result is < 60 seconds, then 3 digits after decimal.
    local run_time=$((${2/./} - ${1/./}))
    if [[ $run_time -lt 10000000 ]]; then printf -v run_time "%07d" $run_time; echo "${run_time:0:1}.${run_time: -6:4}s";
    elif [[ $run_time -lt 60000000 ]]; then echo "${run_time:0:2}.${run_time: -6:3}s";
    elif [[ $run_time -lt 3600000000 ]]; then echo "$((run_time % 3600000000 / 60000000))m $((run_time % 60000000 / 1000000))s";
    elif [[ $run_time -lt 86400000000 ]]; then echo "$((run_time / 3600000000))h $((run_time % 3600000000 / 60000000))m $((run_time % 60000000 / 1000000))s";
    else echo "$((run_time / 86400000000))d $((run_time / 3600000000 % 24))h $((run_time % 3600000000 / 60000000))m"; fi
}

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
    local dir_vars=("BACKUP_DIR" "PLEX_DIR")
    for dir in "${dir_vars[@]}"; do
        local clean_dir="${!dir}"
        clean_dir="${clean_dir%/}"  # Remove trailing slashes.
        eval "$dir=\"$clean_dir\""  # Update the variable with the cleaned path.
        if [ ! -d "$clean_dir" ]; then
            echo_ts "[ERROR] Directory not found: '$clean_dir/'"
            exit 1
        fi
    done
    if [[ $RUN_TARBALL_BACKUP_UPON_COMPLETION = true ]] && [[ ! -f "/boot/config/plugins/user.scripts/scripts/$NAME_OF_TARBALL_SCRIPT/script" ]]; then
        echo_ts "[WARNING] COULD NOT FIND '$NAME_OF_TARBALL_SCRIPT' SCRIPT IN UNRAID USER-SCRIPTS! CANNOT RUN TARBALL BACKUP AFTER SCRIPT COMPLETION!"
    fi
}

# Function to record the "start time of backup" when 'run_time' is calculated at end of backup.
start_backup() {
    script_start_time=$EPOCHREALTIME
    echo_ts "[PLEX DB BACKUP STARTED]"
}

# Function to send backup start notification to Unraid's Web GUI.
send_start_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex DB Back Up Started."
}

# Function to stop Plex docker.
stop_plex() {
    echo_ts "Stopping Plex docker..."
    docker stop "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex docker stopped."
}

# Function to back up the files.
backup_files() {
    local backup_files_start_time=$EPOCHREALTIME
    backup_path="$BACKUP_DIR/$(COMPLETE_SUBDIR_NAME)"
    echo_ts "Copying files to: '$backup_path'"
    mkdir -p "$backup_path"
    BACKUP_COMMAND
    backup_path_filesize=$(du -hs "$backup_path" | awk '{print $1}')
    echo_ts "Copied $backup_path_filesize of files in $(run_timer $backup_files_start_time $EPOCHREALTIME). "
}

# Function to start Plex docker.
start_plex() {
    echo_ts "Starting Plex docker..."
    docker start "$PLEX_DOCKER_NAME" >/dev/null
    echo_ts "Plex docker started."
}

# Function to set permissions on the backup sub-directory and files.
set_permissions() {
    echo_ts "Running 'chmod -R $PERMISSIONS' on backup sub-directory..."
    chmod -R $PERMISSIONS "$backup_path"
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

# Function to print backup completed message to console with the 'run_time' variable.
complete_backup() {
    run_time=$(run_timer $script_start_time $EPOCHREALTIME)
    echo_ts "[PLEX DB BACKUP COMPLETE] Run Time: $run_time. Folder size: $backup_path_filesize."
}

# Function to send backup success notification to Unraid's Web GUI.
send_success_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex DB Back Up Complete." -d "Run time: $run_time. Folder size: $backup_path_filesize"
}

# Function to run Plex's tarball backup once script is completed.
run_plex_tarball_backup() {
    if [[ -f "/boot/config/plugins/user.scripts/scripts/$NAME_OF_TARBALL_SCRIPT/script" ]]; then
        if [[ "$DAYS_TO_RUN_TARBALL_SCRIPT_ON" =~ "$(date +%w)" ]]; then
            bash "/boot/config/plugins/user.scripts/scripts/$NAME_OF_TARBALL_SCRIPT/script"
        fi
    else
        echo_ts "[ERROR] COULD NOT FIND '$NAME_OF_TARBALL_SCRIPT' IN UNRAID'S USER-SCRIPTS. CANNOT RUN PLEX TARBALL BACKUP SCRIPT."
    fi
}

################################################################################
#                            BEGIN PROCESSING HERE                             #
################################################################################

# Abort script if there are active users on the Plex server.
if [[ $ABORT_SCRIPT_RUN_IF_ACTIVE_PLEX_SESSIONS == true ]]; then abort_script_run_due_to_active_plex_sessions; fi

# Verify that $BACKUP_DIR and $PLEX_DIR are valid paths.
verify_valid_path_variables

# Print backup start message to console. This is consided the "start of the backup" when 'run_time' is calculated. 
start_backup

# Send backup started notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_START_MSG == true ]]; then send_start_msg_to_unraid_webgui; fi

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER == true ]]; then stop_plex; fi

# Copy the files from Plex to the backup sub-directory.
backup_files

# Start Plex Docker before doing anything else.
if [[ $STOP_PLEX_DOCKER == true ]]; then start_plex; fi

# Set permissions for the backup directory and its contents.
if [[ $PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then set_permissions; fi

# Delete old backups.
if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+$ ]]; then delete_old_backups; fi

# Print backup completed message to console with the 'run_time' for the backup.
complete_backup

# Send backup completed notification to Unraid's Web GUI.
if [[ $UNRAID_WEBGUI_SUCCESS_MSG == true ]]; then send_success_msg_to_unraid_webgui; fi

# Run Tarball Backup immediately after script completion.
if [[ $RUN_TARBALL_BACKUP_UPON_COMPLETION == true ]]; then run_plex_tarball_backup; fi

# Exit with success.
exit 0

#!/bin/bash

# This script is designed to backup only the essential files that *DO* require the Plex server to be shut down.
# By default, these are the two DB files 'com.plexapp.plugins.library.db' 'com.plexapp.plugins.library.blobs.db' and 'Preferences.xml'.
# The files are placed in their own sub-directory (with a timestamp of the current time) within the specified backup directory.

################################################################################
#                        USER CONFIG (REQUIRED TO EDIT)                        #
################################################################################
BACKUP_DIR="/mnt/user/Backup/Plex DB Backups"  # Backup directory.
PLEX_DIR="/mnt/primary/appdata/plex"  # Plex appdata directory.
PLEX_DOCKER_NAME="plex"  # Name of Plex docker (required for 'STOP_PLEX_DOCKER' variable).
HOURS_TO_KEEP_BACKUPS_FOR="95"  # Delete backups older than this many hours. [Hours=Days|72=3|96=4|120=5|144=6|168=7|336=14|720=30] (you may also comment out or delete to disable)
# ----------------- ALSO RUN TARBALL BACKUP AFTER DB BACKUP ------------------ # Below is an alternative to setting individual cron jobs for both backup scripts.
RUN_TARBALL_BACKUP_UPON_COMPLETION=false  # Set to 'true' (without quotes) to run the Tarball backup script in Unraid's user-scripts immediately after this script. 
DAYS_TO_RUN_TARBALL_SCRIPT_ON="1 4"  # Days of the week to trigger the Tarball backup script on (separated by spaces). Same as would be in cron (most systems: 0 = Sunday, 6 = Saturday).
NAME_OF_TARBALL_SCRIPT="Plex Tarball Backup"  # Name of the Tarball backup script in Unraid's user-scripts. (click on cogwheel, will be BASENAME dir. ie last dir of: '/boot/config/plugins/user.scripts/scripts/Plex Tarball Backup')

################################################################################
#             OPTIONAL ADVANCED USER CONFIG (NOT REQUIRED TO EDIT)             #
################################################################################
STOP_PLEX_DOCKER=true  # Shutdown Plex docker before backup and restart it after backup. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
UNRAID_WEBGUI_START_MSG=true  # Send backup start message to the Unraid Web GUI. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to 'true' (without quotes) to use. (you may also comment out or delete to disable)
USE_LOCK_FILE=false  # Set to 'true' (without quotes) to enable use of lock file to prevent overlapping backups. 'rm /tmp/plex_db_backup.tmp' to delete lock file if required. (you may also comment out or delete to disable)
PERMISSIONS="777"  # Set to any 3 or 4 digit value to have chmod set those permissions on the backup sub-directory and files. (you may also comment out or delete to disable)
SUBDIR_TEXT="Plex DB Backup"  # OPTIONALLY customize the text for the backup sub-directory name. As a precaution, the script only deletes old backups that match this pattern.
TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for backup sub-directory name.
COMPLETE_SUBDIR_NAME() { echo "[$(TIMESTAMP)] $SUBDIR_TEXT"; }  # OPTIONALLY customize the complete backup sub-directory name with the TIMESTAMP and SUBDIR_TEXT.
BACKUP_COMMAND() {  # OPTIONALLY customize the function that copies the files. Use '$backup_path' to specify the full backup path. '$plex_pms_dir' is the 'Plex Media Server' dir in plex appdata.
    cp "$plex_pms_dir/Preferences.xml" "$backup_path/Preferences.xml"
    cp "$plex_pms_dir/Plug-in Support/Databases/com.plexapp.plugins.library.db" "$backup_path/com.plexapp.plugins.library.db"
    cp "$plex_pms_dir/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db" "$backup_path/com.plexapp.plugins.library.blobs.db"
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
        echo_ts "[ERROR] Could not connect to Plex server. Aborting Plex DB Backup."
        exit 1
    elif [[ $response == *'state="playing"'* ]] || ( [[ $INCLUDE_PAUSED_SESSIONS == true ]] && [[ $response == *'state="paused"'* ]] ); then
        echo_ts "Active users on Plex server. Aborting Plex DB Backup."
        exit 0
    fi
}

# Function to verify user variables and handle errors.
prepare_backup() {
    if [[ $USE_LOCK_FILE == true ]] && [[ -f "/tmp/plex_db_backup.tmp" ]]; then
        echo_ts "[ERROR] Plex DB backup is currently active! Lock file can be removed by typing 'rm /tmp/plex_db_backup.tmp'. Exiting."
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
    if [[ $RUN_TARBALL_BACKUP_UPON_COMPLETION == true ]] && [[ ! -f "/boot/config/plugins/user.scripts/scripts/$NAME_OF_TARBALL_SCRIPT/script" ]]; then
        echo_ts "[WARNING] COULD NOT FIND '$NAME_OF_TARBALL_SCRIPT' SCRIPT IN UNRAID USER-SCRIPTS! CANNOT RUN TARBALL BACKUP AFTER SCRIPT COMPLETION!"
        echo_ts "Pausing for 10 seconds..."
        sleep 10
    fi
}

# Function to send backup start notification to Unraid's Web GUI.
send_start_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex DB Back Up Started."
}

# Function to record the "start time of backup" when 'run_time' is calculated at end of backup.
start_backup() {
    script_start_time=$EPOCHREALTIME
    if [[ $USE_LOCK_FILE == true ]]; then touch "/tmp/plex_db_backup.tmp"; fi
    echo_ts "[PLEX DB BACKUP STARTED]"
    if [[ $UNRAID_WEBGUI_START_MSG == true ]]; then send_start_msg_to_unraid_webgui; fi
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

# Function to set permissions on the backup sub-directory and files.
set_permissions() {
  # echo_ts "Running 'chmod -R $PERMISSIONS' on backup sub-directory..."
    chmod -R $PERMISSIONS "$backup_path"
  # echo_ts "Successfully set permissions on backup sub-directory."
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
                echo_ts "Deleted old Plex DB Backup: '$(basename "$dir")'"
            fi
        fi
    done
}

# Function to send backup success notification to Unraid's Web GUI.
send_success_msg_to_unraid_webgui() {
    /usr/local/emhttp/webGui/scripts/notify -i normal -e "Plex DB Back Up Complete." -d "Run time: $run_time. Folder size: $backup_path_filesize"
}

# Function to print backup completed message to console with the 'run_time' variable.
complete_backup() {
    run_time=$(run_timer $script_start_time $EPOCHREALTIME)
    if [[ $USE_LOCK_FILE == true ]]; then rm "/tmp/plex_db_backup.tmp"; fi
    echo_ts "[PLEX DB BACKUP COMPLETE] Run Time: $run_time. Folder size: $backup_path_filesize."
    if [[ $UNRAID_WEBGUI_SUCCESS_MSG == true ]]; then send_success_msg_to_unraid_webgui; fi
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

# Verify correctly set user variables and other error handling.
prepare_backup

# Print backup start message to console. This is consided the "start of the backup" when 'run_time' is calculated. 
start_backup

# Stop Plex Docker.
if [[ $STOP_PLEX_DOCKER == true ]]; then stop_plex; fi

# Copy the files from Plex to the backup sub-directory.
backup_files

# Start Plex Docker.
if [[ $STOP_PLEX_DOCKER == true ]]; then start_plex; fi

# Delete old backups.
if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+$ ]]; then delete_old_backups; fi

# Print backup completed message to console with the 'run_time' for the backup.
complete_backup

# Run Tarball Backup immediately after script completion.
if [[ $RUN_TARBALL_BACKUP_UPON_COMPLETION == true ]]; then run_plex_tarball_backup; fi

# Exit with success.
exit 0

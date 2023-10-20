# Unraid_Plex_Backup
User scripts for Unraid to backup only the essential Plex data. There are two users scripts that are similar yet have key differences. Choose either or both depending on your needs.

[plex_db_backup.sh](plex_db_backup.sh) is designed for backing up the files that require Plex to be shutdown. By default these are the two main Database files (`com.plexapp.plugins.library.db` and `com.plexapp.plugins.library.blobs.db`) and `Preferences.xml` file. It backs these files up in a sub-folder with a timestamp of the current time to the specified backup directory. This is a script that is usually ran as a nightly cron job during off peak hours of Plex usage.

[plex_tarball_backup.sh](plex_tarball_backup.sh) is designed for backing up the files that do **not** require Plex to be shutdown. By default these are the `Media` and `Metadata` folders. It backs these files up in a .tar file with a timestamp of the current time to the specified backup directory. This is a script that does not need to be ran as often (ie once a week) as the backups are significantly larger and take much longer.

# Unraid_Plex_Backup

If using a ZFS filesystem, I recommend using [this script](https://github.com/Blasman/Unraid_Docker_ZFS_AIO_Backup) that I made instead. Otherwise, read on...

User scripts for Unraid to backup only the essential Plex server data and minimize Plex server downtime. There are two users scripts that are similar yet have key differences. Choose either or both depending on your needs.

[plex_db_backup.sh](plex_db_backup.sh) is designed for backing up the files that require Plex to be shutdown. By default these are the two main Database files (`com.plexapp.plugins.library.db` and `com.plexapp.plugins.library.blobs.db`) and `Preferences.xml` file. It backs these files up in a sub-folder with a timestamp of the current time to the specified backup directory. This is a script that is usually ran as a nightly cron job during off peak hours of Plex usage.

[plex_tarball_backup.sh](plex_tarball_backup.sh) is designed for backing up the files that do **not** require Plex to be shutdown. By default these are the `Media` and `Metadata` folders. It backs these files up in a .tar file with a timestamp of the current time to the specified backup directory. This is a script that does not need to be ran as often (ie once a week) as the backups are significantly larger and take much longer.

I have attempted to make every part of the scripts user customizable. Please inspect the `user config` at the beginning of the scripts to see all of the available options. These are also great back-up scripts for anything in general because of all the options available.

## Logic

The Plex files `com.plexapp.plugins.library.db` `com.plexapp.plugins.library.blobs.db` and `Preferences.xml` are the most crucial files that need to be backed up. We don't *need* these files in a .tar file. These files are a small filesize relative to modern available storage space. Taring these files gives no real advantage and just adds an extra step of untarring them later if you want to restore the files and/or edit/analyze them in any way. Likewise, adding a timestamp directly to the filename also adds an extra step of having to rename the files if you want to restore them later. Therefor, we simply take these files and store them in a *folder* with the current timestamp. If we need to restore them later, it's much easier and faster (copy and paste). As these are also the only files that require the Plex server to be shut down in order to properly back them up, Plex downtime becomes minimal. The Plex docker will stop *immediately* before the filecopy process and start *immediately* after it. This generally takes less than 10 seconds in my experience.

The Plex folders `Media` and `Metadata` are generally large directories with *several* files. Therefor, creating a tar file for these files generally makes more sense rather than attempting to copy several small files to a backup folder. The general opinion is also that the Plex server does *not* need to be stopped before backing up these folders. These folders can be rather large depending on the size of your Plex library (and settings) and can even takes hours to copy if you have a large enough library. Therefor, we minimize Plex downtime further by not shutting down the Plex server when tarring these files.

Why not just one script instead of two? While it is true that both scripts contain almost completely similar functions and variables, the intent of use is for Unraid's User-Scripts plug-in which allows you to set a unique cron job for each individual script (run them on different schedules). This keeps things much simpler. In the User-Scripts plug-in, you create a new user script, then copy and paste the script into it, then edit the `user config` portion of the script, save, and then set the cron schedule. Easy peasy. Having them as separate scripts also allows you to run either type of backup "on demand" in the user-scripts plugin.

If you prefer to have just one cron schedule for both scripts, that is also possible by editing the `user config` in `plex_db_backup.sh` to have `plex_tarball_backup.sh` run immediately after `plex_db_backup.sh` has finished processing on specified days of the week.

## Log Example

```
[2023_10_28 05:00:03.230] [PLEX DB BACKUP STARTED]
[2023_10_28 05:00:03.246] Stopping Plex docker...
[2023_10_28 05:00:07.503] Plex docker stopped.
[2023_10_28 05:00:07.505] Copying files to: '/mnt/user/Backup/Plex DB Backups/[2023_10_28@05.00.07] Plex DB Backup'
[2023_10_28 05:00:10.361] Copied 1.4G of files in 2.857s. 
[2023_10_28 05:00:10.385] Starting Plex docker...
[2023_10_28 05:00:10.557] Plex docker started.
[2023_10_28 05:00:10.565] Deleted old Plex DB Backup: '[2023_10_24@05.00.06] Plex DB Backup'
[2023_10_28 05:00:10.666] [PLEX DB BACKUP COMPLETE] Run Time: 7.435s. Folder size: 1.4G.
```

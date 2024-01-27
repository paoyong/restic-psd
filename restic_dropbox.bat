set USER=C:\Users\pao
set REPO=%USER%\Dropbox\backups\restic_dropbox
set SCRIPTS=%USER%\Dropbox\backup_scripts
set SNAPSHOTS=4

restic backup --files-from="%SCRIPTS%\restic_files_to_backup_dropbox.txt" -r %REPO% --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"

restic -r %REPO% forget --keep-last %SNAPSHOTS% --prune --password-file="%SCRIPTS%\restic_password"
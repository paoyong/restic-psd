set USER=C:\Users\pao
set REPO=backups\restic_daily
set SCRIPTS=C:\Users\pao\Dropbox\backup_scripts
set SNAPSHOTS_DAILY=30
set SNAPSHOTS_BIHOURLY=16
set FILE=%SCRIPTS%\restic_files_to_backup_daily.txt

restic backup --files-from="%FILE%" -r E:\%REPO% --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"
restic backup --files-from="%FILE%" -r F:\%REPO% --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"
restic backup %USER%\Desktop -r C:\Users\pao\Dropbox\backups\restic_daily --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"

restic -r E:\%REPO% forget --keep-last %SNAPSHOTS_DAILY% --prune --password-file="%SCRIPTS%\restic_password"
restic -r F:\%REPO% forget --keep-last %SNAPSHOTS_DAILY% --prune --password-file="%SCRIPTS%\restic_password"
restic -r C:\Users\pao\Dropbox\backups\restic_daily forget --keep-last 3 --prune --password-file="%SCRIPTS%\restic_password"

restic -r E:\%REPO% forget --keep-last %SNAPSHOTS_BIHOURLY% --prune --password-file="%SCRIPTS%\restic_password"
restic -r F:\%REPO% forget --keep-last %SNAPSHOTS_BIHOURLY% --prune --password-file="%SCRIPTS%\restic_password"
restic -r C:\Users\pao\Dropbox\backups\restic_bihourly forget --keep-last 2 --prune --password-file="%SCRIPTS%\restic_password"
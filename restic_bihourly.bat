set USER=C:\Users\pao
set REPO=backups\restic_bihourly
set SCRIPTS=C:\Users\pao\Dropbox\backup_scripts
set SNAPSHOTS=16

restic backup %USER%\Desktop\ -r E:\%REPO% --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"
restic backup %USER%\Desktop\ -r F:\%REPO% --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"
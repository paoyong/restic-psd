@echo off
setlocal enabledelayedexpansion
call "%~dp0config.bat"

set INCLUDES=
if not "%KEYWORDS%"=="" (
    for %%K in (%KEYWORDS%) do set INCLUDES=!INCLUDES! --include=*%%K*
)

restic backup --files-from="%SCRIPTS%\folders_watched.txt" -r %REPO_DAILY% %INCLUDES% --exclude-file="%SCRIPTS%\restic_exclude.txt" --password-file="%SCRIPTS%\restic_password"

restic -r %REPO_DAILY%    forget --keep-last %SNAPSHOTS_DAILY%    --prune --password-file="%SCRIPTS%\restic_password"
restic -r %REPO_BIHOURLY% forget --keep-last %SNAPSHOTS_BIHOURLY% --prune --password-file="%SCRIPTS%\restic_password"
endlocal

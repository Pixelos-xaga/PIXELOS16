@echo off
setlocal enabledelayedexpansion

REM ============================================
REM   PixelOS ROM Auto-Download Script
REM   Fully automated - no SSH needed!
REM ============================================

set PROJECT=agile-outlook-481719-c1
set VM_NAME=pixelos
set VM_USER=angxddeep
set DOWNLOAD_DIR=%USERPROFILE%\Downloads\PixelOS_ROM

echo ============================================
echo   PixelOS ROM Auto-Download Script
echo ============================================
echo.

REM Check if gcloud is installed
where gcloud >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: gcloud CLI not found!
    echo.
    echo Please install Google Cloud SDK from:
    echo https://cloud.google.com/sdk/docs/install
    echo.
    pause
    exit /b 1
)

REM Set default zone
set ZONE=us-central1-c
echo Zone set to: %ZONE%

echo.
echo What would you like to download?
echo   1) Image files only (for fastboot package)
echo   2) Recovery build (OTA ZIP + boot images)
echo.
set /p CHOICE="Enter your choice (1-2): "
echo.

if "%CHOICE%"=="1" (
    set PREPARE_CHOICE=1
    set DESC=Image files
) else if "%CHOICE%"=="2" (
    set PREPARE_CHOICE=2
    set DESC=Recovery build
) else (
    echo ERROR: Invalid choice. Please select 1 or 2.
    pause
    exit /b 1
)

echo ============================================
echo === Selected: %DESC%
echo ============================================
echo.

REM Create download directory
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"

echo ============================================
echo Step 1: Preparing package on VM...
echo ============================================
echo.

REM Clear output file
if exist "%TEMP%\prepare_output.txt" del "%TEMP%\prepare_output.txt"

REM Run prepare script on VM remotely
echo === Running preparation script on VM...
gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="cd ~/PIXELOS16 && echo %PREPARE_CHOICE% | bash prepare_download.sh" > "%TEMP%\prepare_output.txt" 2>&1
type "%TEMP%\prepare_output.txt"
set ERRORCODE=!ERRORLEVEL!

if !ERRORCODE! NEQ 0 (
    echo ERROR: Failed to prepare package on VM!
    echo.
    echo Make sure prepare_download.sh exists in /home/angxddeep/PIXELOS16/ on your VM
    pause
    exit /b 1
)

echo === Preparation complete!
echo.

REM Extract the package path from output
for /f "tokens=*" %%a in ('findstr /C:"Location:" "%TEMP%\prepare_output.txt"') do (
    set LINE=%%a
    for /f "tokens=2 delims: " %%b in ("!LINE!") do set REMOTE_FILE=%%b
)

if "!REMOTE_FILE!"=="" (
    echo ERROR: Could not find package path!
    echo.
    echo Preparation output:
    type "%TEMP%\prepare_output.txt"
    pause
    exit /b 1
)

echo === Package location: !REMOTE_FILE!
echo.

echo ============================================
echo Step 2: Downloading package...
echo ============================================
echo.

REM Download the file
gcloud compute scp %VM_USER%@%VM_NAME%:!REMOTE_FILE! "%DOWNLOAD_DIR%\" --project=%PROJECT% --zone=%ZONE%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Download failed!
    pause
    exit /b 1
)

echo.
echo === Download complete!
echo.

REM Get filename from path
for %%F in ("!REMOTE_FILE!") do set ARCHIVE_NAME=%%~nxF
set LOCAL_ARCHIVE=%DOWNLOAD_DIR%\!ARCHIVE_NAME!

echo ============================================
echo Step 3: Extracting files...
echo ============================================
echo.

if exist "!LOCAL_ARCHIVE!" (
    cd /d "%DOWNLOAD_DIR%"
    tar -xzf "!ARCHIVE_NAME!"
    
    if %ERRORLEVEL% EQU 0 (
        echo === Extraction complete!
        echo.
        
        REM Delete local archive
        echo === Cleaning up local archive...
        del "!ARCHIVE_NAME!"
        echo === Local archive deleted.
        
    ) else (
        echo ERROR: Extraction failed!
        pause
        exit /b 1
    )
) else (
    echo ERROR: Archive not found at !LOCAL_ARCHIVE!
    pause
    exit /b 1
)

echo.
echo ============================================
echo Step 4: Cleaning up VM...
echo ============================================
echo.

REM Delete the archive from VM
echo === Deleting archive from VM...
gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="rm -f ~/prepare_download_output.tar.gz 2>/dev/null; echo 'Cleanup done'"

if %ERRORLEVEL% EQU 0 (
    echo === VM archive deleted.
) else (
    echo WARNING: Could not delete archive from VM (non-critical)
)

REM Optionally delete the entire downloads folder on VM
set /p CLEANUP="Delete entire downloads folder on VM? (y/N): "
if /i "!CLEANUP!"=="y" (
    for %%F in ("!REMOTE_FILE!") do set DOWNLOADS_DIR=%%~dpF
    echo === Deleting !DOWNLOADS_DIR! on VM...
    gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="rm -rf !DOWNLOADS_DIR:~0,-1!"
    echo === VM downloads folder deleted.
)

echo.
echo ============================================
echo === SUCCESS!
echo ============================================
echo.
echo Files saved to:
echo     %DOWNLOAD_DIR%
echo.

REM List extracted contents
echo Contents:
if exist "%DOWNLOAD_DIR%\images_*" (
    dir /b "%DOWNLOAD_DIR%\images_*"
)
if exist "%DOWNLOAD_DIR%\recovery_*" (
    dir /b "%DOWNLOAD_DIR%\recovery_*"
)

echo.
echo === Opening download folder...
explorer "%DOWNLOAD_DIR%"

echo.
echo ============================================
echo All done! Archive cleaned from VM.
echo ============================================
pause

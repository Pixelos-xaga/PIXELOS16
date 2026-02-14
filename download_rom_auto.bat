@echo off
setlocal enabledelayedexpansion

REM ============================================
REM   PixelOS ROM Auto-Download Script
REM   Uploads to Google Cloud Storage for fast browser download!
REM ============================================

set PROJECT=agile-outlook-481719-c1
set VM_NAME=pixelos
set VM_USER=angxddeep
set GCS_BUCKET=pixelos-downloads-angxddeep

REM ============================================
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
echo GCS Bucket: gs://%GCS_BUCKET%/
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

echo ============================================
echo Step 1: Preparing package on VM...
echo ============================================
echo.

REM Clear output file
if exist "%TEMP%\prepare_output.txt" del "%TEMP%\prepare_output.txt"

REM Run prepare script on VM remotely
echo === Running preparation script on VM...
echo.
echo [This may take several minutes if ROM needs to build...]
echo.

REM Run with real-time output (unbuffered)
gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="cd ~/PIXELOS16 && echo %PREPARE_CHOICE% | bash prepare_download.sh"

set ERRORCODE=!ERRORLEVEL!
echo.
echo [SSH exit code: !ERRORCODE!]
echo.

REM Check if the output file was created (more reliable than exit code)
echo === Verifying build output...
for /f "tokens=*" %%a in ('gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="cat /tmp/pixelos_last_build.txt 2>/dev/null || echo NOTFOUND"') do (
    set VERIFY_PATH=%%a
)

if "!VERIFY_PATH!"=="NOTFOUND" (
    echo ERROR: Build failed - no output file found!
    pause
    exit /b 1
)

if !ERRORCODE! NEQ 0 (
    echo WARNING: SSH exited with code !ERRORCODE! but build appears successful.
    echo Continuing anyway...
    echo.
)

echo === Preparation complete!
echo.

REM Get the package path from the VM
echo === Getting package location from VM...
for /f "tokens=*" %%a in ('gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="cat /tmp/pixelos_last_build.txt"') do (
    set REMOTE_FILE=%%a
)

if "!REMOTE_FILE!"=="" (
    echo ERROR: Could not find package path on VM!
    echo.
    echo Make sure the build completed successfully.
    pause
    exit /b 1
)

echo === Package location: !REMOTE_FILE!
echo.

REM Extract filename from path
for %%F in ("!REMOTE_FILE!") do set ARCHIVE_NAME=%%~nxF

echo ============================================
echo Step 2: Uploading to Google Cloud Storage...
echo ============================================
echo.

echo === Uploading to GCS bucket...
gcloud compute ssh %VM_USER%@%VM_NAME% --project=%PROJECT% --zone=%ZONE% --command="gsutil cp !REMOTE_FILE! gs://%GCS_BUCKET%/"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Failed to upload to GCS!
    echo.
    echo Make sure gsutil is installed and authenticated on the VM.
    echo Run: gcloud auth login
    echo.
    pause
    exit /b 1
)

echo === Upload complete!
echo.

REM Generate the public URL (bucket is not public by default, user needs to make it public or use signed URL)
set GCS_URL=https://storage.googleapis.com/%GCS_BUCKET%/%ARCHIVE_NAME%

echo ============================================
echo === SUCCESS!
echo ============================================
echo.
echo Your file has been uploaded to Google Cloud Storage:
echo.
echo   File: %ARCHIVE_NAME%
echo   Bucket: gs://%GCS_BUCKET%/
echo.
echo === Download Links ===
echo.
echo GCS Console URL:
echo   https://console.cloud.google.com/storage/browser/%GCS_BUCKET%/?project=%PROJECT%
echo.
echo Direct Download URL (if bucket is public):
echo   %GCS_URL%
echo.
echo gsutil command:
echo   gsutil cp gs://%GCS_BUCKET%/%ARCHIVE_NAME% .
echo.
echo === Instructions ===
echo 1. Open the GCS Console URL above in your browser
echo 2. Click on the file to download it
echo 3. OR use the gsutil command for fastest download
echo.
echo ============================================
echo.

REM Optionally open browser
echo Opening GCS Console in browser...
start https://console.cloud.google.com/storage/browser/%GCS_BUCKET%/?project=%PROJECT%

echo.
echo ============================================
pause

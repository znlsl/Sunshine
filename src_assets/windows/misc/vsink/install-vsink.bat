@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem =========================================================
rem VB-Cable (virtual microphone) installer
rem - Downloads VB-Cable driver pack
rem - Extracts it to a temp folder
rem - Runs setup interactively (more reliable than undocumented silent flags)
rem - Returns a meaningful exit code to the caller
rem =========================================================

rem Check for administrator privileges
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Please run this script as administrator.
    exit /b 1
)

rem Quick detection: registry (64-bit + 32-bit view) OR audio endpoint
powershell -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; $reg=@('HKLM:\SOFTWARE\VB-Audio\Cable','HKLM:\SOFTWARE\WOW6432Node\VB-Audio\Cable','HKLM:\SOFTWARE\VB-Audio','HKLM:\SOFTWARE\WOW6432Node\VB-Audio'); if($reg | ForEach-Object{Test-Path $_} | Where-Object{$_} | Select-Object -First 1){ exit 0 }; try { $d=Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'VB-?Cable|VB-Audio Virtual Cable|CABLE' }; if($d){ exit 0 } } catch {}; exit 1" >nul 2>&1
if not errorlevel 1 (
    echo [INFO] VB-Cable appears to be already installed. Skipping.
    exit /b 0
)

set "temp_dir=%TEMP%\vb_cable_install"
set "zip_name=VBCABLE_Driver_Pack45.zip"
set "download_url=https://download.vb-audio.com/Download_CABLE/%zip_name%"
set "zip_path=%temp_dir%\%zip_name%"
set "log_path=%temp_dir%\install.log"

if not exist "%temp_dir%" mkdir "%temp_dir%" >nul 2>&1

rem Allow offline/manual download: if zip already exists, reuse it.
if exist "%zip_path%" (
    for %%A in ("%zip_path%") do set "zip_size=%%~zA"
    if not "!zip_size!"=="0" (
        echo [INFO] Using existing package: "%zip_path%"
        goto :Extract
    )
)

echo [INFO] Downloading VB-Cable package...
echo [INFO] URL: %download_url%
echo [INFO] Output: "%zip_path%"

set "VSINK_URL=%download_url%"
set "VSINK_OUT=%zip_path%"
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}; $url=$env:VSINK_URL; $out=$env:VSINK_OUT; try { if(Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue){ Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing } else { (New-Object System.Net.WebClient).DownloadFile($url,$out) }; exit 0 } catch { Write-Host ('[ERROR] Download failed: ' + $_.Exception.Message); exit 1 }" 1>>"%log_path%" 2>&1

if errorlevel 1 goto :DownloadFailed
if not exist "%zip_path%" goto :DownloadFailed
for %%A in ("%zip_path%") do set "zip_size=%%~zA"
if "!zip_size!"=="0" goto :DownloadFailed

:Extract
echo [INFO] Extracting package...
set "VSINK_ZIP=%zip_path%"
set "VSINK_DEST=%temp_dir%"
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $zip=$env:VSINK_ZIP; $dest=$env:VSINK_DEST; try { if(Get-Command Expand-Archive -ErrorAction SilentlyContinue){ Expand-Archive -Path $zip -DestinationPath $dest -Force } else { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory($zip,$dest) }; exit 0 } catch { Write-Host ('[ERROR] Extract failed: ' + $_.Exception.Message); exit 1 }" 1>>"%log_path%" 2>&1

if errorlevel 1 goto :ExtractFailed

rem Decide which setup to run
set "setup_exe="
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "[Environment]::Is64BitOperatingSystem"`) do set "is_64bit_os=%%i"
if /i "%is_64bit_os%"=="True" (
    if exist "%temp_dir%\VBCABLE_Setup_x64.exe" set "setup_exe=%temp_dir%\VBCABLE_Setup_x64.exe"
) else (
    if exist "%temp_dir%\VBCABLE_Setup.exe" set "setup_exe=%temp_dir%\VBCABLE_Setup.exe"
)
if not defined setup_exe (
    if exist "%temp_dir%\VBCABLE_Setup_x64.exe" set "setup_exe=%temp_dir%\VBCABLE_Setup_x64.exe"
    if not defined setup_exe if exist "%temp_dir%\VBCABLE_Setup.exe" set "setup_exe=%temp_dir%\VBCABLE_Setup.exe"
)
if not defined setup_exe goto :SetupMissing

echo [INFO] Running installer (interactive): "%setup_exe%"
echo [INFO] If the installer opens, click "Install Driver" and wait until it completes.
"%setup_exe%"
set "installer_exit=!errorlevel!"
echo [INFO] Installer exit code: !installer_exit!

rem Verify install again (registry OR device presence)
powershell -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; $reg=@('HKLM:\SOFTWARE\VB-Audio\Cable','HKLM:\SOFTWARE\WOW6432Node\VB-Audio\Cable','HKLM:\SOFTWARE\VB-Audio','HKLM:\SOFTWARE\WOW6432Node\VB-Audio'); if($reg | ForEach-Object{Test-Path $_} | Where-Object{$_} | Select-Object -First 1){ exit 0 }; try { $d=Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'VB-?Cable|VB-Audio Virtual Cable|CABLE' }; if($d){ exit 0 } } catch {}; exit 1" >nul 2>&1
if errorlevel 1 goto :VerifyFailed

echo [SUCCESS] VB-Cable installation completed.
rd /s /q "%temp_dir%" >nul 2>&1
exit /b 0

:DownloadFailed
echo [ERROR] Failed to download VB-Cable package.
echo [ERROR] Check network/DNS/proxy restrictions, or manually download the zip by browser and place it here:
echo [ERROR]   "%zip_path%"
echo [ERROR] Log kept at: "%log_path%"
echo [ERROR] Temp folder kept at: "%temp_dir%"
exit /b 2

:ExtractFailed
echo [ERROR] Failed to extract VB-Cable package.
echo [ERROR] The downloaded zip might be incomplete or blocked by antivirus.
echo [ERROR] Log kept at: "%log_path%"
echo [ERROR] Temp folder kept at: "%temp_dir%"
exit /b 3

:SetupMissing
echo [ERROR] VB-Cable setup executable not found after extraction.
echo [ERROR] Expected "%temp_dir%\\VBCABLE_Setup_x64.exe" or "%temp_dir%\\VBCABLE_Setup.exe"
echo [ERROR] Temp folder kept at: "%temp_dir%"
exit /b 4

:VerifyFailed
echo [ERROR] Installer finished, but VB-Cable was not detected afterwards.
echo [ERROR] The driver installation may have been blocked (driver signing/policy/antivirus), or the installer was cancelled.
echo [ERROR] Log kept at: "%log_path%"
echo [ERROR] Temp folder kept at: "%temp_dir%"
exit /b 5

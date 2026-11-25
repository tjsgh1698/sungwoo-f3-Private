@echo off
rem F3 MES uploader every 10 min
schtasks /Create /F /SC MINUTE /MO 10 /TN "F3 MES Uploader" /TR "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%~dp0uploader.ps1\""
echo Done. See uploader.log
pause

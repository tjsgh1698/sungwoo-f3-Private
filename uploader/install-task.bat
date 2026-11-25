@echo off
rem 10분마다 업로더 실행 등록 (현재 사용자, 로그인 상태에서)
schtasks /Create /F /SC MINUTE /MO 10 /TN "F3 MES Uploader" /TR "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%~dp0uploader.ps1\""
echo 등록 완료. 기록은 uploader.log 에 남습니다.
pause

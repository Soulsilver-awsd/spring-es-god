@echo off
setlocal
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] No se encontro Node.js en el PATH.
  pause
  exit /b 1
)

echo ==============================================================
echo   Billetera Digital Distribuida - Presentacion Web Interactiva
echo   Abriendo http://localhost:3333 ...
echo ==============================================================

start "" cmd /c "timeout /t 2 /nobreak >nul && start http://localhost:3333"
node "%~dp0presentacion-web\server.mjs"

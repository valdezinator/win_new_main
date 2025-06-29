@echo off
echo ========================================
echo Resonance MSIX Release Build Script
echo ========================================
echo.

echo Step 1: Generating certificate...
powershell -ExecutionPolicy Bypass -File simple_cert.ps1

if not exist "resonance_cert.pfx" (
    echo Error: Certificate generation failed
    echo Please run as Administrator
    pause
    exit /b 1
)

echo.
echo Step 2: Building Windows app...
flutter build windows

if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to build Windows app
    pause
    exit /b 1
)

echo.
echo Step 3: Building MSIX package...
dart run msix:create

if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to build MSIX
    pause
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo ========================================
echo.
echo Your MSIX file is located at:
echo C:\Users\shrey\Downloads\resonance.msix
echo.
echo To install on another machine:
echo 1. Copy the certificate file (resonance_cert.pfx)
echo 2. Install the certificate: certutil -importpfx resonance_cert.pfx
echo 3. Install the MSIX: Add-AppxPackage -Path resonance.msix
echo.
pause 
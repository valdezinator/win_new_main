@echo off
echo ========================================
echo Generating Certificate using OpenSSL
echo ========================================
echo.

REM Check if OpenSSL is available
openssl version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo OpenSSL not found. Please install OpenSSL or use the PowerShell script.
    echo You can download OpenSSL from: https://slproweb.com/products/Win32OpenSSL.html
    pause
    exit /b 1
)

echo Generating private key...
openssl genrsa -out resonance_private.key 2048

if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to generate private key
    pause
    exit /b 1
)

echo Generating certificate...
openssl req -new -x509 -key resonance_private.key -out resonance_cert.crt -days 365 -subj "/CN=Resonance Development Certificate"

if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to generate certificate
    pause
    exit /b 1
)

echo Converting to PFX format...
openssl pkcs12 -export -out resonance_cert.pfx -inkey resonance_private.key -in resonance_cert.crt -passout pass:2008

if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to convert to PFX
    pause
    exit /b 1
)

echo Cleaning up temporary files...
del resonance_private.key
del resonance_cert.crt

echo.
echo ========================================
echo Certificate generated successfully!
echo ========================================
echo Certificate file: resonance_cert.pfx
echo Password: 2008
echo.
pause 
# Generate Self-Signed Certificate for MSIX
# Run this script as Administrator

# Import required modules
Import-Module Microsoft.PowerShell.Security -Force
Import-Module PKI -Force

$certSubject = "CN=Resonance Development Certificate"
$certPath = ".\resonance_cert.pfx"
$certPassword = "2008"

Write-Host "Generating self-signed certificate for MSIX signing..." -ForegroundColor Green

try {
    # Generate the certificate using the correct certificate store
    $cert = New-SelfSignedCertificate -Type Custom -Subject $certSubject -KeyUsage DigitalSignature -FriendlyName "Resonance Development Certificate" -CertStoreLocation "Cert:\LocalMachine\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

    if ($cert) {
        # Export the certificate to PFX file
        $securePassword = ConvertTo-SecureString -String $certPassword -Force -AsPlainText
        Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $securePassword

        Write-Host "Certificate generated successfully!" -ForegroundColor Green
        Write-Host "Certificate file: $certPath" -ForegroundColor Yellow
        Write-Host "Certificate password: $certPassword" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "1. Certificate is already configured in pubspec.yaml" -ForegroundColor White
        Write-Host "2. Run: flutter build msix" -ForegroundColor White
        Write-Host "3. Install the certificate on target machines if needed" -ForegroundColor White
    } else {
        Write-Host "Failed to generate certificate" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error generating certificate: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure you're running as Administrator" -ForegroundColor Yellow
    exit 1
} 
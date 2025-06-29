# Simple Certificate Generation
# Run as Administrator

Write-Host "Generating simple self-signed certificate..." -ForegroundColor Green

try {
    # Create a simple self-signed certificate
    $cert = New-SelfSignedCertificate -DnsName "Resonance" -CertStoreLocation "Cert:\LocalMachine\My" -Type Custom -KeyUsage DigitalSignature -FriendlyName "Resonance Certificate"
    
    if ($cert) {
        Write-Host "Certificate created successfully!" -ForegroundColor Green
        Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Cyan
        
        # Export to PFX
        $password = ConvertTo-SecureString -String "2008" -Force -AsPlainText
        Export-PfxCertificate -Cert $cert -FilePath ".\resonance_cert.pfx" -Password $password
        
        Write-Host "Certificate exported to: resonance_cert.pfx" -ForegroundColor Green
        Write-Host "Password: 2008" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure you're running as Administrator" -ForegroundColor Yellow
} 
# Alternative Certificate Generation Script
# Run this script as Administrator

param(
    [string]$Subject = "CN=Resonance Development Certificate",
    [string]$OutputPath = ".\resonance_cert.pfx",
    [string]$Password = "2008"
)

Write-Host "Generating self-signed certificate for MSIX signing..." -ForegroundColor Green

try {
    # Method 1: Try using New-SelfSignedCertificate with explicit module loading
    Write-Host "Attempting to load certificate modules..." -ForegroundColor Yellow
    
    # Load the certificate provider
    $null = Get-PSDrive -PSProvider Certificate -ErrorAction SilentlyContinue
    if (-not $?) {
        Write-Host "Certificate provider not available, trying alternative method..." -ForegroundColor Yellow
    }
    
    # Generate certificate using LocalMachine store
    $cert = New-SelfSignedCertificate -Type Custom -Subject $Subject -KeyUsage DigitalSignature -FriendlyName "Resonance Development Certificate" -CertStoreLocation "Cert:\LocalMachine\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") -ErrorAction Stop
    
    if ($cert) {
        Write-Host "Certificate generated successfully!" -ForegroundColor Green
        Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Cyan
        
        # Export to PFX
        $securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText
        Export-PfxCertificate -Cert $cert -FilePath $OutputPath -Password $securePassword -ErrorAction Stop
        
        Write-Host "Certificate exported to: $OutputPath" -ForegroundColor Green
        Write-Host "Password: $Password" -ForegroundColor Yellow
        
        return 0
    }
} catch {
    Write-Host "Error with New-SelfSignedCertificate: $($_.Exception.Message)" -ForegroundColor Red
    
    # Method 2: Try using makecert (if available)
    Write-Host "Trying alternative certificate generation method..." -ForegroundColor Yellow
    
    try {
        # Check if makecert is available
        $makecertPath = Get-Command makecert -ErrorAction SilentlyContinue
        if ($makecertPath) {
            Write-Host "Using makecert to generate certificate..." -ForegroundColor Yellow
            
            # Generate certificate using makecert
            $tempCer = ".\temp_cert.cer"
            $tempPvk = ".\temp_cert.pvk"
            
            # Generate certificate and private key
            & makecert -r -pe -n $Subject -ss MY -a sha256 -cy end -sky signature -sv $tempPvk $tempCer
            
            if (Test-Path $tempCer -and Test-Path $tempPvk) {
                # Convert to PFX using pvk2pfx
                $pvk2pfxPath = Get-Command pvk2pfx -ErrorAction SilentlyContinue
                if ($pvk2pfxPath) {
                    & pvk2pfx -pvk $tempPvk -spc $tempCer -pfx $OutputPath -po $Password
                    
                    # Clean up temp files
                    Remove-Item $tempCer -ErrorAction SilentlyContinue
                    Remove-Item $tempPvk -ErrorAction SilentlyContinue
                    
                    Write-Host "Certificate generated using makecert!" -ForegroundColor Green
                    return 0
                }
            }
        }
    } catch {
        Write-Host "makecert method also failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "All certificate generation methods failed." -ForegroundColor Red
    Write-Host "Please ensure you're running as Administrator and have certificate tools installed." -ForegroundColor Yellow
    return 1
} 
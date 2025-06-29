# MSIX Certificate Generation and Distribution Guide

## Overview
This guide explains how to generate certificates for signing and distributing your Resonance MSIX package.

## Certificate Options

### 1. Self-Signed Certificate (Development/Testing)
- **Use case**: Development, testing, internal distribution
- **Pros**: Free, quick to generate, good for testing
- **Cons**: Shows security warning, not trusted by default

### 2. Code Signing Certificate (Production)
- **Use case**: Public distribution, Microsoft Store
- **Pros**: Trusted by Windows, no security warnings
- **Cons**: Costs money (~$200-500/year), requires identity verification

## Quick Start (Self-Signed Certificate)

### Option A: Automated Build
1. Run the automated build script:
   ```bash
   build_release.bat
   ```

### Option B: Manual Steps
1. **Generate Certificate** (Run as Administrator):
   ```powershell
   powershell -ExecutionPolicy Bypass -File generate_certificate.ps1
   ```

2. **Build MSIX Package**:
   ```bash
   flutter build msix
   ```

## Production Certificate (Microsoft Store/Public Distribution)

### 1. Purchase a Code Signing Certificate
- **Recommended providers**:
  - DigiCert
  - Sectigo
  - GlobalSign
  - Comodo

### 2. Install the Certificate
- Download the certificate from your provider
- Install it in your certificate store
- Update `pubspec.yaml` with the certificate path

### 3. Update pubspec.yaml
```yaml
msix_config:
  # ... existing config ...
  certificate_path: C:\path\to\your\certificate.pfx
  certificate_password: your_certificate_password
```

## Distribution Methods

### 1. Direct Installation
```powershell
# Install certificate first
certutil -importpfx resonance_cert.pfx

# Install MSIX
Add-AppxPackage -Path resonance.msix
```

### 2. Microsoft Store
- Requires code signing certificate
- Submit through Microsoft Partner Center
- Automatic updates and distribution

### 3. Enterprise Distribution
- Use Microsoft Intune
- Deploy through Group Policy
- Use Windows Package Manager

## Troubleshooting

### Common Issues

1. **Certificate not found**
   - Ensure certificate path is correct in `pubspec.yaml`
   - Check if certificate file exists

2. **Build fails**
   - Run `flutter clean` before building
   - Ensure all dependencies are installed

3. **Installation fails**
   - Install certificate on target machine
   - Check Windows version compatibility
   - Verify certificate is trusted

### Security Considerations

1. **Keep certificate secure**
   - Store certificate password safely
   - Don't commit certificate files to version control
   - Use environment variables for passwords

2. **Certificate expiration**
   - Monitor certificate expiration dates
   - Renew before expiration
   - Update MSIX packages with new certificates

## File Structure
```
project_root/
├── generate_certificate.ps1    # Certificate generation script
├── build_release.bat          # Automated build script
├── resonance_cert.pfx         # Generated certificate (after running script)
├── pubspec.yaml              # Updated with certificate config
└── MSIX_BUILD_README.md      # This file
```

## Next Steps
1. Choose your certificate type (self-signed vs. code signing)
2. Run the appropriate build process
3. Test installation on target machines
4. Distribute according to your needs 
# This script helps you set up your .env file
# Run this script in PowerShell: .\setup_env.ps1

$envFile = ".env"
$exampleFile = ".env.example"

# Check if .env file already exists
if (Test-Path $envFile) {
    Write-Host ".env file already exists. Do you want to overwrite it? (y/n)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -ne 'y') {
        Write-Host "Setup cancelled." -ForegroundColor Red
        exit
    }
}

# Read values from .env.example
$exampleContent = Get-Content -Path $exampleFile -Raw
$exampleVars = @{}

# Parse the example file to get variable names
$exampleContent -split "`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $varName = $parts[0].Trim()
            $exampleValue = $parts[1].Trim()
            $exampleVars[$varName] = $exampleValue
        }
    }
}

# Prompt user for values
$newContent = @"
# Supabase Configuration
# Replace the values below with your actual Supabase credentials

"@

foreach ($var in $exampleVars.Keys) {
    $defaultValue = $exampleVars[$var]
    $prompt = "Enter value for $var"
    if ($defaultValue) {
        $prompt += " (default: $defaultValue)"
    }
    $prompt += ": "
    
    $value = Read-Host -Prompt $prompt
    if ([string]::IsNullOrWhiteSpace($value) -and $defaultValue) {
        $value = $defaultValue
    }
    
    $newContent += "$var=$value`n"
}

# Write to .env file
Set-Content -Path $envFile -Value $newContent.Trim()

Write-Host "`n.env file has been created/updated successfully!" -ForegroundColor Green
Write-Host "Please make sure to keep this file secure and never commit it to version control." -ForegroundColor Yellow

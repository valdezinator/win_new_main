# Check if Supabase CLI is installed
if (!(Get-Command supabase -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Supabase CLI..."
    winget install Supabase.CLI
}

# Login to Supabase (if not already logged in)
supabase login

# Link to your project (if not already linked)
# Replace YOUR_PROJECT_REF with your actual project reference
# supabase link --project-ref YOUR_PROJECT_REF

# Deploy the function
supabase functions deploy get-signed-url --no-verify-jwt

Write-Host "Function deployed successfully!" 
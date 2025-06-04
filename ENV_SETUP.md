# Environment Setup Guide

This guide will help you set up the required environment variables for the Music Streaming App.

## Prerequisites

- Flutter SDK installed
- Supabase project created
- Supabase URL and anon key

## Setup Instructions

### Option 1: Using the Setup Script (Recommended for Windows)

1. Open PowerShell in the project root directory
2. Run the following command to allow script execution (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```
3. Run the setup script:
   ```powershell
   .\setup_env.ps1
   ```
4. Follow the prompts to enter your Supabase URL and anon key

### Option 2: Manual Setup

1. Create a new file named `.env` in the project root directory
2. Copy the contents from `.env.example` to `.env`
3. Replace the placeholder values with your actual Supabase credentials

## Required Environment Variables

- `SUPABASE_URL`: Your Supabase project URL (e.g., `https://xxxxxxxxxxxxx.supabase.co`)
- `SUPABASE_ANON_KEY`: Your Supabase anon/public key

## Security Notes

- Never commit the `.env` file to version control
- The `.env` file is already included in `.gitignore`
- Keep your Supabase anon key secure
- For production, consider using environment variables provided by your hosting platform

## Verifying the Setup

1. Run the app in debug mode:
   ```bash
   flutter run
   ```
2. The app should start without any authentication errors
3. If you see any errors about missing environment variables, double-check your `.env` file

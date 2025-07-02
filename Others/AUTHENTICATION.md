# Authentication System

This document describes the comprehensive authentication system implemented in the Music App.

## Overview

The authentication system provides multiple sign-in options:
- **Google OAuth**: Sign in with Google account
- **Email/Password**: Traditional email and password authentication
- **Email Sign-up**: Create new accounts with email verification

## Features

### 1. Google OAuth Authentication
- Seamless sign-in with Google accounts
- Automatic user profile creation
- Secure token management
- Cross-platform support (Windows, Web)

### 2. Email Authentication
- Email and password sign-in
- Password reset functionality
- Email verification for new accounts
- Secure password validation

### 3. User Registration
- Username and email registration
- Password confirmation
- Terms of service agreement
- Email verification workflow

## File Structure

```
lib/
├── auth/
│   ├── auth_screen.dart          # Main authentication screen
│   ├── email_sign_in_screen.dart # Email sign-in form
│   └── email_sign_up_screen.dart # Email registration form
├── services/
│   └── auth_service.dart         # Authentication service
└── main.dart                     # App entry point with AuthWrapper
```

## Components

### AuthScreen
The main authentication screen that provides:
- Google OAuth sign-in button
- Email sign-in option
- Navigation to sign-up
- Modern, responsive UI design

### EmailSignInScreen
Dedicated email authentication screen with:
- Email and password fields
- Form validation
- Password reset functionality
- Error handling

### EmailSignUpScreen
User registration screen featuring:
- Username, email, and password fields
- Password confirmation
- Terms agreement checkbox
- Comprehensive validation

### AuthService
Centralized authentication service providing:
- User management
- Session handling
- Token storage
- Profile updates

## Usage

### Basic Authentication Flow

1. **App Launch**: AuthWrapper checks for existing session
2. **Authentication**: User chooses sign-in method
3. **Session Management**: Tokens are stored securely
4. **Navigation**: Automatic redirection to main app

### Google OAuth Flow

```dart
// Sign in with Google
await AuthService().signInWithGoogle(
  redirectTo: 'app://win.new.music/auth-callback'
);
```

### Email Authentication Flow

```dart
// Sign in with email
final response = await AuthService().signInWithEmail(
  email: 'user@example.com',
  password: 'password123'
);

// Sign up with email
final response = await AuthService().signUpWithEmail(
  email: 'user@example.com',
  password: 'password123',
  data: {'username': 'username'}
);
```

## Security Features

- **Secure Token Storage**: Tokens stored using SharedPreferences
- **Session Management**: Automatic session validation
- **Password Validation**: Strong password requirements
- **Error Handling**: Comprehensive error messages
- **Input Validation**: Client-side form validation

## UI/UX Features

- **Modern Design**: Spotify-inspired dark theme
- **Responsive Layout**: Works on different screen sizes
- **Loading States**: Visual feedback during authentication
- **Error Display**: Clear error messages
- **Smooth Navigation**: Seamless screen transitions

## Configuration

### Supabase Setup

1. Configure Google OAuth in Supabase dashboard
2. Set up email templates for verification
3. Configure redirect URLs for OAuth
4. Set up password policies

### Environment Variables

Ensure your `.env` file contains:
```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

## Error Handling

The system handles various authentication errors:
- Invalid credentials
- Email not confirmed
- User already exists
- Network errors
- Server errors

## Future Enhancements

- Multi-factor authentication
- Social media login (Facebook, Twitter)
- Biometric authentication
- Single sign-on (SSO)
- Account linking

## Support

For issues or questions about the authentication system, please refer to the Supabase documentation or create an issue in the project repository. 
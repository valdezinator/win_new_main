import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get current user
  User? get currentUser => _supabase.auth.currentUser;

  /// Get current session
  Session? get currentSession => _supabase.auth.currentSession;

  /// Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  /// Sign in with email and password
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign up with email and password
  Future<AuthResponse> signUpWithEmail(String email, String password, {Map<String, dynamic>? data}) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  /// Sign in with Google OAuth
  Future<void> signInWithGoogle({String? redirectTo}) async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    // Clear stored tokens
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Update user profile
  Future<UserResponse> updateProfile({Map<String, dynamic>? data}) async {
    return await _supabase.auth.updateUser(
      UserAttributes(data: data),
    );
  }

  /// Listen to auth state changes
  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;

  /// Save session tokens
  Future<void> saveSession(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', session.accessToken);
    if (session.refreshToken != null) {
      await prefs.setString('refresh_token', session.refreshToken!);
    }
  }

  /// Get stored access token
  Future<String?> getStoredAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Clear stored tokens
  Future<void> clearStoredTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  /// Get user metadata
  Map<String, dynamic>? get userMetadata => currentUser?.userMetadata;

  /// Get username from metadata
  String? get username {
    final metadata = userMetadata;
    return metadata?['username'] as String?;
  }

  /// Get email
  String? get email => currentUser?.email;

  /// Get user ID
  String? get userId => currentUser?.id;
} 
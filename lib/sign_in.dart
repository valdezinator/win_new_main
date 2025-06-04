import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';
import 'dart:io' show Platform, InternetAddress, HttpServer, ContentType;
import 'dart:async';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            setState(() => _errorMessage = null);
          },
          textColor: Colors.white,
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      if (kIsWeb) {
        // Web flow remains the same
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: '${Uri.base.origin}/callback',
        );
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Desktop: Use local server logic
        HttpServer? server;
        final ports = [8000, 8001, 8002, 8003, 8004];
        for (final port in ports) {
          try {
            server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              port,
              shared: true,
            );
            break;
          } catch (e) {
            if (port == ports.last) {
              _showError('Failed to bind to any available port. Please check your firewall settings or try again later.');
              setState(() => _isLoading = false);
              return;
            }
            continue;
          }
        }
        if (server == null) {
          _showError('Failed to create server');
          setState(() => _isLoading = false);
          return;
        }
        try {
          StreamSubscription? subscription;
          subscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
            if (data.event == AuthChangeEvent.signedIn) {
              subscription?.cancel();
              if (mounted) {
                setState(() => _isLoading = false);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              }
            }
          });
          await Supabase.instance.client.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: 'http://localhost:${server.port}/auth-callback',
          );
          final request = await server.first;
          final callbackUrl = request.uri.toString();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('<html><body>You can now close this window.</body></html>');
          await request.response.close();
          await Supabase.instance.client.auth.getSessionFromUrl(Uri.parse(callbackUrl));
          await Future.delayed(const Duration(seconds: 20));
          if (Supabase.instance.client.auth.currentUser == null) {
            _showError('Authentication did not complete successfully.');
            setState(() => _isLoading = false);
          }
        } catch (e) {
          _showError('Sign in failed: $e');
          setState(() => _isLoading = false);
        } finally {
          await server.close(force: true);
        }
      } else {
        // Mobile flow
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'app://win.new.music/auth-callback',
        );
      }
      // After successful sign in, save the token
      final prefs = await SharedPreferences.getInstance();
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await prefs.setString('access_token', session.accessToken);
      }
      // Navigate to home page
      if (mounted && (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux))) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
      }
    } catch (error) {
      _showError('Sign in failed: ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // Close loading dialog if it's showing
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  Future<void> _handleSignUp() async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        _showError('Please enter both email and password.');
        setState(() => _isLoading = false);
        return;
      }
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user == null) {
        _showError('Sign up failed.');
        setState(() => _isLoading = false);
        return;
      }
      // Navigate to home page
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
    } catch (e) {
      _showError('Sign up failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF181B20),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
            children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Cresca',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              const Text(
                  'Sign Up',
                style: TextStyle(
                  color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 40),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Email',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 18,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF23262B),
                    border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Password',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 18,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF23262B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Already got an account? ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => const SignInScreen()),
                            );
                          },
                          child: const Text(
                            'Sign in',
                            style: TextStyle(
                              color: Color(0xFF3CB371),
                              fontSize: 16,
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Montserrat',
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Sign Up'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontFamily: 'Montserrat',
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text('Sign in with Google'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: null, // Apple sign in not available yet
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontFamily: 'Montserrat',
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text('Sign in with Apple(not available yet)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

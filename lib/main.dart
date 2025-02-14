import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';  // Add this import
import 'home_page.dart';
import 'sign_in.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';

Future<void> main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Configure platform channels to use platform thread
  SystemChannels.platform.setMethodCallHandler((call) async {
    if (call.method.startsWith('com.ryanheise.just_audio')) {
      // Ensure we're on the main thread
      await SystemChannels.platform.invokeMethod('runOnUIThread');
    }
    return null;
  });

  // Initialize Just Audio Background
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
    notificationColor: Colors.grey[900],
  );

  // Initialize Supabase using your project's URL and anon key.
  await Supabase.initialize(
    url: 'https://yaysfbsmvtyqpbfhxstj.supabase.co', // Replace with your Supabase URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlheXNmYnNtdnR5cXBiZmh4c3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI0NDQ3NDgsImV4cCI6MjA0ODAyMDc0OH0.7d_RsoyQ5RN6Whj6flbd5W0CSLiUpJ6HfRFVEnQKsf8', // Replace with your Supabase anon key
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Map<String, dynamic>> checkLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    // Get last played song state
    final lastPlayedSong = prefs.getString('last_played_song');
    final wasPlaying = prefs.getBool('was_playing') ?? false;
    
    return {
      'isLoggedIn': accessToken != null,
      'lastPlayedSong': lastPlayedSong != null ? Map<String, dynamic>.from(
        json.decode(lastPlayedSong)
      ) : null,
      'wasPlaying': wasPlaying,
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: FutureBuilder<Map<String, dynamic>>(
        future: checkLoginState(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          final state = snapshot.data ?? {'isLoggedIn': false};
          if (state['isLoggedIn']) {
            return HomeScreen(
              initialSong: state['lastPlayedSong'],
              autoplay: state['wasPlaying'],
            );
          } else {
            return LoginScreen();
          }
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isBusy = false;
  String _errorMessage = '';

  Future<void> _authenticate() async {
    setState(() {
      _isBusy = true;
      _errorMessage = '';
    });
    HttpServer? server;
    try {
      // Start local server on port 8000
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8000);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to bind local server: $e';
        _isBusy = false;
      });
      return;
    }
    try {
      // Declare mutable subscription before assigning.
      StreamSubscription? subscription;
      subscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        debugPrint("Auth state changed: ${data.event}");
        if (data.event == AuthChangeEvent.signedIn) {
          subscription?.cancel();
          setState(() {
            _isBusy = false;
          });
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const HomeScreen(),
            ),
          );
        }
      });

      // Launch OAuth flow with redirectTo pointing to the local server.
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'http://localhost:8000/auth-callback', // Must match your Supabase settings
      );

      // Wait for the OAuth callback request.
      final request = await server.first;
      // Capture the callback url.
      final callbackUrl = request.uri.toString();
      // Send a simple web response.
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html><body>You can now close this window.</body></html>');
      await request.response.close();
      
      // Attempt to recover the session using the callback URL.
      debugPrint("Recovering session from callback: $callbackUrl");
      await Supabase.instance.client.auth.getSessionFromUrl(Uri.parse(callbackUrl));

      // Increase delay to allow more time for the auth state update.
      await Future.delayed(const Duration(seconds: 20));

      // If still not signed in, show error.
      if (Supabase.instance.client.auth.currentUser == null) {
        debugPrint("No auth update received after timeout");
        setState(() {
          _errorMessage = 'Authentication did not complete successfully.';
          _isBusy = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Authentication failed: $e';
        _isBusy = false;
      });
    }
    await server.close(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login with OAuth2'),
      ),
      body: Center(
        child: _isBusy
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _authenticate,
                    child: const Text('Login with OAuth'),
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
      ),
    );
  }
}

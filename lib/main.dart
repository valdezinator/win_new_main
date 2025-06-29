import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'main_app.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'services/security_service.dart';
import 'services/ad_manager_service.dart';
import 'services/audio_service.dart';
import 'services/analytics_service.dart';

// Create a global instance of AudioService
final AudioService _audioService = AudioService();

// Load environment variables from .env file
Future<void> loadEnv() async {
  try {
    await dotenv.load(fileName: ".env");
    
    // Validate required environment variables
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    
    if (supabaseUrl == null || supabaseAnonKey == null) {
      throw Exception('Missing required environment variables. Please check your .env file.');
    }
    
    if (!supabaseUrl.startsWith('http')) {
      throw Exception('Invalid SUPABASE_URL in .env file');
    }
  } catch (e) {
    // In production, you might want to log this to a service like Sentry
    debugPrint('Error loading environment variables: $e');
    rethrow; // Re-throw to prevent the app from starting with invalid config
  }
}

// Create a custom window listener class
class CustomWindowListener extends WindowListener {
  final AnalyticsService analyticsService;

  CustomWindowListener(this.analyticsService);

  @override
  void onWindowMoved() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    analyticsService.logWindowState(
      state: 'moved',
      size: size,
      position: position,
    );
  }

  @override
  void onWindowResized() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    analyticsService.logWindowState(
      state: 'resized',
      size: size,
      position: position,
    );
  }

  @override
  void onWindowMaximized() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    analyticsService.logWindowState(
      state: 'maximized',
      size: size,
      position: position,
    );
  }

  @override
  void onWindowUnmaximized() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    analyticsService.logWindowState(
      state: 'unmaximized',
      size: size,
      position: position,
    );
  }

  @override
  void onWindowMinimized() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    analyticsService.logWindowState(
      state: 'minimized',
      size: size,
      position: position,
    );
  }

  @override
  void onWindowRestored() async {
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    analyticsService.logWindowState(
      state: 'restored',
      size: size,
      position: position,
    );
  }
}

Future<void> main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SecurityService
  await SecurityService().initialize();
  
  // Load environment variables
  await loadEnv();

  // Initialize Supabase using environment variables FIRST
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize ad Service AFTER Supabase
  await AdManagerService().initialize(_audioService.player);

  // Initialize window manager for Windows
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Error initializing window manager: $e');
      // Continue with the app even if window manager fails
    }
  }

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

  // Initialize analytics service
  final analyticsService = AnalyticsService();
  await analyticsService.initialize();
  
  // Listen to window state changes
  windowManager.addListener(CustomWindowListener(analyticsService));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _analyticsService = AnalyticsService();
  User? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginState();
  }

  Future<void> _checkLoginState() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        _user = session.user;
        await _analyticsService.logUserSession(_user);
      } else {
        _user = null;
        await _analyticsService.logUserSession(null);
      }
    } catch (e) {
      debugPrint('Error checking login state: $e');
      _user = null;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _user == null ? const LoginScreen() : const MainApp();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isBusy = false;
  String _errorMessage = '';
  final _securityService = SecurityService();

  Future<void> _authenticate() async {
    setState(() {
      _isBusy = true;
      _errorMessage = '';
    });

    HttpServer? server;
    // Try a range of ports starting from 8000
    final ports = [8000, 8001, 8002, 8003, 8004];
    
    for (final port in ports) {
      try {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4, 
          port,
          shared: true  // Allow port sharing
        );
        debugPrint('Successfully bound to port $port');
        break;
      } catch (e) {
        if (port == ports.last) {
          setState(() {
            _errorMessage = 'Failed to bind to any available port. Please check your firewall settings or try again later.';
            _isBusy = false;
          });
          return;
        }
        debugPrint('Failed to bind to port $port, trying next port...');
        continue;
      }
    }

    if (server == null) {
      setState(() {
        _errorMessage = 'Failed to create server';
        _isBusy = false;
      });
      return;
    }

    try {
      StreamSubscription? subscription;
      subscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        debugPrint("Auth state changed: ${data.event}");
        if (data.event == AuthChangeEvent.signedIn) {
          subscription?.cancel();
          
          // Save session securely
          final session = data.session;
          if (session != null) {
            await _securityService.saveSession(
              session.accessToken,
              session.refreshToken ?? ''
            );
          }

          if (mounted) {
            setState(() {
              _isBusy = false;
            });
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const MainApp(),
              ),
            );
          }
        }
      });

      // Launch OAuth flow with redirectTo pointing to the local server.
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'http://localhost:8000/auth-callback',
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
    } finally {
      await server.close(force: true);
    }
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

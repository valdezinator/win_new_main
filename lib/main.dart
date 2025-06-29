import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'main_app.dart';
import 'auth/auth_screen.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'services/security_service.dart';
import 'services/ad_manager_service.dart';
import 'services/audio_service.dart';
import 'services/analytics_service.dart';
import 'package:uni_links/uni_links.dart';

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
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String?>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _checkLoginState();
    _listenToAuthChanges();
    _listenToIncomingLinks();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      debugPrint("Auth state changed: ${data.event}");
      
      if (data.event == AuthChangeEvent.signedIn) {
        _user = data.session?.user;
        await _analyticsService.logUserSession(_user);
      } else if (data.event == AuthChangeEvent.signedOut) {
        _user = null;
        await _analyticsService.logUserSession(null);
      }
      
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _listenToIncomingLinks() {
    _linkSubscription = linkStream.listen((String? link) async {
      if (link != null && link.startsWith('app://win.new.music/auth-callback')) {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(Uri.parse(link));
        } catch (e) {
          debugPrint('Error handling OAuth callback: $e');
        }
      }
    });
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

    return _user == null ? const AuthScreen() : const MainApp();
  }
}

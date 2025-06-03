import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:feedback/feedback.dart';
import 'main_app.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'sign_in.dart';
import 'services/network_service.dart';
import 'services/monitoring_service.dart';
import 'services/window_service.dart';
import 'services/system_tray_service.dart';
import 'services/startup_service.dart';
import 'services/offline_service.dart';
import 'config/firebase_options.dart';
import 'config/env_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  try {
    // Ensure Flutter bindings are initialized
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('Flutter bindings initialized');

    // Load environment variables
    try {
      await dotenv.load(fileName: ".env");
      await EnvConfig.initialize();
      debugPrint('Environment variables loaded');
    } catch (e) {
      debugPrint('Error loading environment variables: $e');
      // Continue without env vars for now
    }

    // Initialize Firebase only for non-Windows platforms
    if (!Platform.isWindows) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('Firebase initialized');
      } catch (e) {
        debugPrint('Error initializing Firebase: $e');
      }
    } else {
      debugPrint('Skipping Firebase initialization on Windows');
    }

    // Initialize monitoring services
    try {
      final monitoringService = MonitoringService();
      await monitoringService.initialize();
      debugPrint('Monitoring service initialized');
    } catch (e) {
      debugPrint('Error initializing monitoring service: $e');
    }

    // Initialize network service
    try {
      await NetworkService().initialize();
      debugPrint('Network service initialized');
    } catch (e) {
      debugPrint('Error initializing network service: $e');
    }

    // Initialize window service for desktop platforms
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        await WindowService().initialize();
        debugPrint('Window service initialized');
        
        // Initialize system tray only if not on Windows
        if (!Platform.isWindows) {
          await SystemTrayService().initialize();
          debugPrint('System tray initialized');
        } else {
          debugPrint('Skipping system tray initialization on Windows');
        }
        
        // Initialize startup service
        await StartupService().initialize();
        debugPrint('Startup service initialized');
      } catch (e, stackTrace) {
        debugPrint('Error initializing window services: $e');
        // Continue with the app even if window service fails
      }
    }

    // Initialize offline service
    try {
      await OfflineService().initialize();
      debugPrint('Offline service initialized');
    } catch (e) {
      debugPrint('Error initializing offline service: $e');
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
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
        notificationColor: Colors.grey[900],
      );
      debugPrint('Just Audio Background initialized');
    } catch (e) {
      debugPrint('Error initializing Just Audio Background: $e');
    }

    // Initialize Supabase
    try {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
      );
      debugPrint('Supabase initialized');
    } catch (e) {
      debugPrint('Error initializing Supabase: $e');
      // Show error UI if Supabase fails to initialize
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Error initializing Supabase: $e'),
            ),
          ),
        ),
      );
      return;
    }

    // Run the app with monitoring
    if (!Platform.isWindows) {
      await SentryFlutter.init(
        (options) {
          options.dsn = EnvConfig.sentryDsn;
          options.tracesSampleRate = 1.0;
          options.environment = 'production';
        },
        appRunner: () => runApp(
          BetterFeedback(
            child: const MyApp(),
          ),
        ),
      );
    } else {
      // Run without Sentry on Windows
      runApp(
        BetterFeedback(
          child: const MyApp(),
        ),
      );
    }
  } catch (e, stackTrace) {
    debugPrint('Fatal error during initialization: $e');
    debugPrint('Stack trace: $stackTrace');
    // Show error UI
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error initializing app: $e'),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Map<String, dynamic>> checkLoginState() async {
    final monitoringService = MonitoringService();
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');

      // Get last played song state
      final lastPlayedSong = prefs.getString('last_played_song');
      final wasPlaying = prefs.getBool('was_playing') ?? false;

      // Log successful login check
      await monitoringService.logEvent(
        name: 'login_check',
        parameters: {
          'is_logged_in': accessToken != null,
          'has_last_played': lastPlayedSong != null,
        },
      );

      return {
        'isLoggedIn': accessToken != null,
        'lastPlayedSong': lastPlayedSong != null ? Map<String, dynamic>.from(
          json.decode(lastPlayedSong)
        ) : null,
        'wasPlaying': wasPlaying,
      };
    } catch (e, stackTrace) {
      // Log error
      await monitoringService.recordError(
        e,
        stackTrace,
        reason: 'Error checking login state',
      );
      rethrow;
    }
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

          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Retry login check
                        (context as Element).markNeedsBuild();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final state = snapshot.data ?? {'isLoggedIn': false};
          if (state['isLoggedIn']) {
            return const MainApp();
          } else {
            return const SignInScreen();
          }
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'main_app.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'sign_in.dart';

Future<void> main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

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
            return const MainApp();
          } else {
            return const SignInScreen();
          }
        },
      ),
    );
  }
}

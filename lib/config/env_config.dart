import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static String get supabaseUrl {
    if (kDebugMode) {
      return dotenv.env['SUPABASE_URL'] ?? '';
    }
    return const String.fromEnvironment('SUPABASE_URL');
  }

  static String get supabaseAnonKey {
    if (kDebugMode) {
      return dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    }
    return const String.fromEnvironment('SUPABASE_ANON_KEY');
  }

  static String get sentryDsn {
    if (kDebugMode) {
      return dotenv.env['SENTRY_DSN'] ?? '';
    }
    return const String.fromEnvironment('SENTRY_DSN');
  }

  static Future<void> initialize() async {
    if (kDebugMode) {
      await dotenv.load(fileName: '.env');
    }
  }
} 
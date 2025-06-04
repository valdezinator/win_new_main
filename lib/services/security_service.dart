import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32_registry/win32_registry.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  late final encrypt.Key _key;
  late final encrypt.IV _iv;
  late final encrypt.Encrypter _encrypter;
  
  Future<String?> _secureRead(String key) async {
    if (Platform.isWindows) {
      try {
        var regKey = Registry.currentUser.createKey(r'Software\Cresca\SecureStorage');
        var value = regKey.getValue(key)?.data;
        regKey.close();
        return value?.toString();
      } catch (e) {
        debugPrint('Error reading from registry: $e');
        return null;
      }
    } else {
      const storage = FlutterSecureStorage();
      return await storage.read(key: key);
    }
  }

  Future<void> _secureWrite(String key, String value) async {
    if (Platform.isWindows) {
      try {
        var regKey = Registry.currentUser.createKey(r'Software\Cresca\SecureStorage');
        regKey.createValue(RegistryValue(key, RegistryValueType.string, value));
        regKey.close();
      } catch (e) {
        debugPrint('Error writing to registry: $e');
        rethrow;
      }
    } else {
      const storage = FlutterSecureStorage();
      await storage.write(key: key, value: value);
    }
  }

  Future<void> initialize() async {
    try {
      // Generate or retrieve encryption key
      String? storedKey = await _secureRead('encryption_key');
      if (storedKey == null) {
        final key = encrypt.Key.fromSecureRandom(32);
        await _secureWrite('encryption_key', base64.encode(key.bytes));
        _key = key;
      } else {
        _key = encrypt.Key(base64.decode(storedKey));
      }
      
      // Initialize IV (Initialization Vector)
      _iv = encrypt.IV.fromLength(16);
      _encrypter = encrypt.Encrypter(encrypt.AES(_key));
    } catch (e) {
      debugPrint('Error initializing SecurityService: $e');
      rethrow;
    }
  }

  // Encrypt sensitive data
  String encryptData(String data) {
    return _encrypter.encrypt(data, iv: _iv).base64;
  }

  // Decrypt sensitive data
  String decryptData(String encryptedData) {
    try {
      return _encrypter.decrypt64(encryptedData, iv: _iv);
    } catch (e) {
      return ''; // Return empty string if decryption fails
    }
  }

  // Secure storage methods
  Future<void> secureWrite(String key, String value) async {
    await _secureWrite(key, encryptData(value));
  }

  Future<String?> secureRead(String key) async {
    final value = await _secureRead(key);
    return value != null ? decryptData(value) : null;
  }

  Future<void> secureDelete(String key) async {
    if (Platform.isWindows) {
      try {
        var regKey = Registry.currentUser.createKey(r'Software\Cresca\SecureStorage');
        if (regKey.getValue(key) != null) {
          regKey.deleteValue(key);
        }
        regKey.close();
      } catch (e) {
        debugPrint('Error deleting secure key: $e');
      }
    } else {
      const storage = FlutterSecureStorage();
      await storage.delete(key: key);
    }
  }

  // Session management
  Future<void> saveSession(String accessToken, String refreshToken) async {
    await secureWrite('access_token', accessToken);
    await secureWrite('refresh_token', refreshToken);
    await secureWrite('session_start', DateTime.now().toIso8601String());
  }

  Future<bool> isSessionValid() async {
    final sessionStart = await secureRead('session_start');
    if (sessionStart == null) return false;
    
    final startTime = DateTime.parse(sessionStart);
    final now = DateTime.now();
    // Session expires after 7 days
    return now.difference(startTime).inDays < 7;
  }

  Future<void> clearSession() async {
    await secureDelete('access_token');
    await secureDelete('refresh_token');
    await secureDelete('session_start');
  }

  // Data retention policy
  Future<void> applyRetentionPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCleanup = prefs.getString('last_data_cleanup');
    final now = DateTime.now();
    
    if (lastCleanup == null || 
        now.difference(DateTime.parse(lastCleanup)).inDays >= 30) {
      // Clear old search history (older than 90 days)
      final searchHistory = prefs.getStringList('search_history') ?? [];
      final filteredHistory = searchHistory.where((item) {
        final data = json.decode(item);
        final searchDate = DateTime.parse(data['timestamp']);
        return now.difference(searchDate).inDays <= 90;
      }).toList();
      
      await prefs.setStringList('search_history', filteredHistory);
      await prefs.setString('last_data_cleanup', now.toIso8601String());
    }
  }

  // GDPR/CCPA compliance
  Future<Map<String, dynamic>> exportUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'search_history': prefs.getStringList('search_history') ?? [],
      'playlists': prefs.getStringList('playlists') ?? [],
      'preferences': {
        'theme': prefs.getString('theme'),
        'language': prefs.getString('language'),
        'quality': prefs.getString('audio_quality'),
      }
    };
  }

  Future<void> deleteUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (Platform.isWindows) {
      try {
        var regKey = Registry.currentUser.createKey(r'Software\Cresca');
        try {
          var secureKey = Registry.currentUser.createKey(r'Software\Cresca\SecureStorage');
          // Delete all values in the secure storage key
          for (var value in secureKey.values) {
            secureKey.deleteValue(value.name);
          }
          secureKey.close();
          // Delete the secure storage key
          regKey.deleteKey('SecureStorage');
        } catch (e) {
          debugPrint('Error cleaning secure storage: $e');
        }
        regKey.close();
      } catch (e) {
        debugPrint('Error accessing registry: $e');
      }
    } else {
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
    }
  }
}

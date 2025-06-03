import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;

  bool _isInitialized = false;
  final SupabaseClient _supabase = Supabase.instance.client;
  final Connectivity _connectivity = Connectivity();
  late Directory _offlineDir;
  late SharedPreferences _prefs;

  // Keys for SharedPreferences
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const String _offlineModeKey = 'offline_mode_enabled';
  static const String _autoDownloadKey = 'auto_download_enabled';

  OfflineService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize offline directory
    final appDir = await getApplicationSupportDirectory();
    _offlineDir = Directory(path.join(appDir.path, 'offline'));
    if (!await _offlineDir.exists()) {
      await _offlineDir.create(recursive: true);
    }

    // Initialize preferences
    _prefs = await SharedPreferences.getInstance();

    // Listen for connectivity changes
    _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);

    _isInitialized = true;
  }

  Future<void> _handleConnectivityChange(ConnectivityResult result) async {
    if (result == ConnectivityResult.none) {
      // Enter offline mode if enabled
      if (await isOfflineModeEnabled()) {
        await enableOfflineMode();
      }
    } else {
      // Check for updates when back online
      await syncOfflineContent();
    }
  }

  Future<bool> isOfflineModeEnabled() async {
    return _prefs.getBool(_offlineModeKey) ?? false;
  }

  Future<void> setOfflineModeEnabled(bool enabled) async {
    await _prefs.setBool(_offlineModeKey, enabled);
    if (enabled) {
      await enableOfflineMode();
    } else {
      await disableOfflineMode();
    }
  }

  Future<bool> isAutoDownloadEnabled() async {
    return _prefs.getBool(_autoDownloadKey) ?? false;
  }

  Future<void> setAutoDownloadEnabled(bool enabled) async {
    await _prefs.setBool(_autoDownloadKey, enabled);
  }

  Future<void> enableOfflineMode() async {
    // Implement offline mode logic
    // This could include:
    // 1. Switching to local database
    // 2. Disabling network requests
    // 3. Showing offline indicator
  }

  Future<void> disableOfflineMode() async {
    // Implement online mode logic
    // This could include:
    // 1. Switching back to remote database
    // 2. Enabling network requests
    // 3. Hiding offline indicator
    // 4. Syncing any pending changes
  }

  Future<void> downloadContent(Map<String, dynamic> content) async {
    if (!_isInitialized) return;

    final contentId = content['id'];
    final contentHash = _generateContentHash(content);
    final contentDir = Directory(path.join(_offlineDir.path, contentId));
    
    if (!await contentDir.exists()) {
      await contentDir.create(recursive: true);
    }

    // Save content metadata
    await File(path.join(contentDir.path, 'metadata.json'))
        .writeAsString(jsonEncode(content));

    // Download associated files (e.g., audio files, images)
    if (content['audio_url'] != null) {
      await _downloadFile(
        content['audio_url'],
        path.join(contentDir.path, 'audio.mp3'),
      );
    }

    if (content['image_url'] != null) {
      await _downloadFile(
        content['image_url'],
        path.join(contentDir.path, 'image.jpg'),
      );
    }

    // Update last sync timestamp
    await _prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _downloadFile(String url, String localPath) async {
    final response = await _supabase.storage
        .from('content')
        .download(path.basename(url));

    if (response != null) {
      await File(localPath).writeAsBytes(response);
    }
  }

  String _generateContentHash(Map<String, dynamic> content) {
    final contentString = jsonEncode(content);
    final bytes = utf8.encode(contentString);
    return sha256.convert(bytes).toString();
  }

  Future<void> syncOfflineContent() async {
    if (!_isInitialized) return;

    final lastSync = _prefs.getInt(_lastSyncKey) ?? 0;
    final lastSyncTime = DateTime.fromMillisecondsSinceEpoch(lastSync);

    // Get content that has been updated since last sync
    final response = await _supabase
        .from('content')
        .select()
        .gt('updated_at', lastSyncTime.toIso8601String());

    if (response != null) {
      final updatedContent = List<Map<String, dynamic>>.from(response);
      for (final content in updatedContent) {
        await downloadContent(content);
      }
    }
  }

  Future<void> removeOfflineContent(String contentId) async {
    if (!_isInitialized) return;

    final contentDir = Directory(path.join(_offlineDir.path, contentId));
    if (await contentDir.exists()) {
      await contentDir.delete(recursive: true);
    }
  }

  Future<bool> isContentAvailableOffline(String contentId) async {
    if (!_isInitialized) return false;

    final contentDir = Directory(path.join(_offlineDir.path, contentId));
    return await contentDir.exists();
  }

  Future<Map<String, dynamic>?> getOfflineContent(String contentId) async {
    if (!_isInitialized) return null;

    final contentDir = Directory(path.join(_offlineDir.path, contentId));
    if (!await contentDir.exists()) return null;

    final metadataFile = File(path.join(contentDir.path, 'metadata.json'));
    if (!await metadataFile.exists()) return null;

    final metadata = jsonDecode(await metadataFile.readAsString());
    return Map<String, dynamic>.from(metadata);
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;
    _isInitialized = false;
  }
} 
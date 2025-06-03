import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

/// Cache duration presets for different types of data
class CacheDurations {
  static const Duration lyrics = Duration(hours: 24);
  static const Duration albumData = Duration(hours: 12);
  static const Duration searchResults = Duration(minutes: 30);
  static const Duration userData = Duration(hours: 6);
  static const Duration playlistData = Duration(hours: 4);
  static const Duration defaultDuration = Duration(days: 1);
}

/// Custom exceptions for different network scenarios
class NetworkException implements Exception {
  final String message;
  final NetworkErrorType type;
  final dynamic originalError;

  NetworkException(this.message, {this.type = NetworkErrorType.unknown, this.originalError});

  @override
  String toString() => 'NetworkException: $message (Type: $type)';
}

enum NetworkErrorType {
  noConnection,
  timeout,
  serverError,
  unauthorized,
  notFound,
  cacheMiss,
  unknown
}

/// A service that handles network state, caching, and offline functionality
class NetworkService with ChangeNotifier {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;

  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  
  // Network state
  bool _isOnline = true;
  ConnectivityResult _connectionType = ConnectivityResult.none;
  bool _isWifi = false;
  
  // Cache settings
  static const int _defaultMaxCacheSize = 100 * 1024 * 1024; // 100MB
  bool _isCacheEnabled = true;
  int _maxCacheSize = _defaultMaxCacheSize;
  
  // Cache state
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  int _currentCacheSize = 0;
  late Directory _cacheDirectory;
  
  // Getters
  bool get isOnline => _isOnline;
  ConnectivityResult get connectionType => _connectionType;
  bool get isWifi => _isWifi;
  bool get isCacheEnabled => _isCacheEnabled;
  int get currentCacheSize => _currentCacheSize;
  int get maxCacheSize => _maxCacheSize;
  
  NetworkService._internal() {
    initialize();
  }
  
  Future<void> initialize() async {
    try {
      // Initialize cache directory
      final appDir = await getApplicationSupportDirectory();
      _cacheDirectory = Directory('${appDir.path}/network_cache');
      if (!await _cacheDirectory.exists()) {
        await _cacheDirectory.create(recursive: true);
      }
      
      // Load cache settings
      final prefs = await SharedPreferences.getInstance();
      _isCacheEnabled = prefs.getBool('cache_enabled') ?? true;
      _maxCacheSize = prefs.getInt('max_cache_size') ?? _defaultMaxCacheSize;
      
      // Initialize connectivity
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
      await _updateConnectionStatus(await _connectivity.checkConnectivity());
      
      // Load cache size and clean old entries
      _currentCacheSize = await _calculateCacheSize();
      await _cleanCache();
      
      // Start periodic cache cleanup
      Timer.periodic(const Duration(hours: 1), (_) => _cleanCache());
    } catch (e) {
      debugPrint('Error initializing NetworkService: $e');
    }
  }

  Future<int> _calculateCacheSize() async {
    int size = 0;
    try {
      await for (final file in _cacheDirectory.list(recursive: true)) {
        if (file is File) {
          size += await file.length();
        }
      }
    } catch (e) {
      debugPrint('Error calculating cache size: $e');
    }
    return size;
  }
  
  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    _connectionType = result;
    _isWifi = result == ConnectivityResult.wifi;
    
    bool wasOnline = _isOnline;
    
    // Check actual internet connectivity with timeout
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      _isOnline = false;
    }
    
    // Notify only if online status changed
    if (wasOnline != _isOnline) {
      notifyListeners();
    }
  }
  
  /// Set maximum cache size
  Future<void> setMaxCacheSize(int sizeInBytes) async {
    _maxCacheSize = sizeInBytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_cache_size', sizeInBytes);
    
    // Clean cache if current size exceeds new limit
    if (_currentCacheSize > sizeInBytes) {
      await _cleanCache();
    }
    
    notifyListeners();
  }
  
  /// Get data with enhanced caching support
  Future<dynamic> getData(String url, {
    Map<String, String>? headers,
    Duration cacheDuration = CacheDurations.defaultDuration,
    bool forceRefresh = false,
    bool usePersistentCache = true,
  }) async {
    // Check memory cache first if enabled and not forcing refresh
    if (_isCacheEnabled && !forceRefresh) {
      final cachedData = _getFromMemoryCache(url);
      if (cachedData != null) {
        return cachedData;
      }
    }
    
    // Check persistent cache if enabled
    if (_isCacheEnabled && usePersistentCache && !forceRefresh) {
      try {
        final cachedData = await _getFromPersistentCache(url);
        if (cachedData != null) {
          // Also update memory cache
          _addToMemoryCache(url, cachedData, cacheDuration);
          return cachedData;
        }
      } catch (e) {
        debugPrint('Error reading from persistent cache: $e');
      }
    }
    
    // If offline and no cache, throw error
    if (!_isOnline) {
      throw NetworkException(
        'No internet connection and data not cached',
        type: NetworkErrorType.noConnection
      );
    }
    
    try {
      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Cache the response if caching is enabled
        if (_isCacheEnabled) {
          _addToMemoryCache(url, data, cacheDuration);
          if (usePersistentCache) {
            await _addToPersistentCache(url, data, cacheDuration);
          }
        }
        
        return data;
      } else {
        throw NetworkException(
          'HTTP Error: ${response.statusCode}',
          type: _getErrorTypeFromStatusCode(response.statusCode)
        );
      }
    } on TimeoutException {
      throw NetworkException(
        'Request timed out',
        type: NetworkErrorType.timeout
      );
    } catch (e) {
      // If we have cached data, return it even if expired
      if (_isCacheEnabled) {
        final cachedData = await _getFromPersistentCache(url, ignoreExpiry: true);
        if (cachedData != null) {
          return cachedData;
        }
      }
      rethrow;
    }
  }

  NetworkErrorType _getErrorTypeFromStatusCode(int statusCode) {
    switch (statusCode) {
      case 401:
        return NetworkErrorType.unauthorized;
      case 404:
        return NetworkErrorType.notFound;
      case >= 500:
        return NetworkErrorType.serverError;
      default:
        return NetworkErrorType.unknown;
    }
  }
  
  /// Get data from memory cache
  dynamic _getFromMemoryCache(String key, {bool ignoreExpiry = false}) {
    if (!_memoryCache.containsKey(key)) return null;
    
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return null;
    
    if (!ignoreExpiry && DateTime.now().isAfter(timestamp)) {
      _removeFromMemoryCache(key);
      return null;
    }
    
    return _memoryCache[key];
  }
  
  /// Add data to memory cache
  void _addToMemoryCache(String key, dynamic data, Duration duration) {
    // Calculate size of new data
    final dataSize = json.encode(data).length;
    
    // If adding this would exceed cache size, remove old entries
    while (_currentCacheSize + dataSize > _maxCacheSize && _memoryCache.isNotEmpty) {
      final oldestKey = _cacheTimestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _removeFromMemoryCache(oldestKey);
    }
    
    // Add to cache
    _memoryCache[key] = data;
    _cacheTimestamps[key] = DateTime.now().add(duration);
    _currentCacheSize += dataSize;
  }
  
  /// Remove data from memory cache
  void _removeFromMemoryCache(String key) {
    if (_memoryCache.containsKey(key)) {
      final dataSize = json.encode(_memoryCache[key]).length;
      _memoryCache.remove(key);
      _cacheTimestamps.remove(key);
      _currentCacheSize -= dataSize;
    }
  }

  /// Get data from persistent cache
  Future<dynamic> _getFromPersistentCache(String key, {bool ignoreExpiry = false}) async {
    final file = File('${_cacheDirectory.path}/${_getCacheFileName(key)}');
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final cacheData = json.decode(content);
      
      if (!ignoreExpiry) {
        final expiry = DateTime.parse(cacheData['expiry']);
        if (DateTime.now().isAfter(expiry)) {
          await file.delete();
          return null;
        }
      }
      
      return cacheData['data'];
    } catch (e) {
      debugPrint('Error reading from persistent cache: $e');
      return null;
    }
  }

  /// Add data to persistent cache
  Future<void> _addToPersistentCache(String key, dynamic data, Duration duration) async {
    final file = File('${_cacheDirectory.path}/${_getCacheFileName(key)}');
    final cacheData = {
      'data': data,
      'expiry': DateTime.now().add(duration).toIso8601String(),
    };
    
    try {
      await file.writeAsString(json.encode(cacheData));
      _currentCacheSize = await _calculateCacheSize();
    } catch (e) {
      debugPrint('Error writing to persistent cache: $e');
    }
  }

  String _getCacheFileName(String key) {
    // Create a safe filename from the URL
    final uri = Uri.parse(key);
    final path = '${uri.host}${uri.path}'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '${path}_${DateTime.now().millisecondsSinceEpoch}.cache';
  }
  
  /// Clean expired cache entries
  Future<void> _cleanCache() async {
    try {
      // Clean memory cache
      final now = DateTime.now();
      final expiredKeys = _cacheTimestamps.entries
          .where((entry) => now.isAfter(entry.value))
          .map((entry) => entry.key)
          .toList();
      
      for (final key in expiredKeys) {
        _removeFromMemoryCache(key);
      }

      // Clean persistent cache
      await for (final file in _cacheDirectory.list()) {
        if (file is File && file.path.endsWith('.cache')) {
          try {
            final content = await file.readAsString();
            final cacheData = json.decode(content);
            final expiry = DateTime.parse(cacheData['expiry']);
            
            if (now.isAfter(expiry)) {
              await file.delete();
            }
          } catch (e) {
            // If file is corrupted, delete it
            await file.delete();
          }
        }
      }

      // Update cache size
      _currentCacheSize = await _calculateCacheSize();
    } catch (e) {
      debugPrint('Error cleaning cache: $e');
    }
  }
  
  /// Clear all cached data
  Future<void> clearCache() async {
    try {
      // Clear memory cache
      _memoryCache.clear();
      _cacheTimestamps.clear();
      
      // Clear persistent cache
      await for (final file in _cacheDirectory.list()) {
        if (file is File && file.path.endsWith('.cache')) {
          await file.delete();
        }
      }
      
      _currentCacheSize = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
  
  /// Dispose resources
  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }
} 
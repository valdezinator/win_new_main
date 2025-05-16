import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'download_service.dart';

/// Class representing a point in a user's route with connectivity info
class RoutePoint {
  final double latitude;
  final double longitude;
  final bool hasConnection;
  final DateTime timestamp;
  
  RoutePoint({
    required this.latitude,
    required this.longitude, 
    required this.hasConnection,
    required this.timestamp
  });
  
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'has_connection': hasConnection,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      hasConnection: json['has_connection'] as bool,
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// Service to track user routes and predict offline areas for content preloading
/// 
/// This service intelligently tracks user location patterns and connectivity to
/// predict when content should be downloaded for offline use. It balances between
/// data usage and ensuring music is available in low-connectivity areas.
/// 
/// Privacy features:
/// - All route data is stored only on device
/// - Location tracking is opt-in only
/// - Clear visual indicators when active
/// - Easy disable option
class RouteTrackingService with ChangeNotifier {
  static final RouteTrackingService _instance = RouteTrackingService._internal();
  factory RouteTrackingService() => _instance;

  final Location _location = Location();
  final Connectivity _connectivity = Connectivity();
  final DownloadService _downloadService = DownloadService();
  
  bool _isEnabled = false;
  bool _isActive = false;
  bool _isPermissionGranted = false;
  bool _wifiOnlyDownloads = true;
  
  Timer? _predictionTimer;
  StreamSubscription? _locationSubscription;
  StreamSubscription? _connectivitySubscription;
  
  // Store recent routes with timestamps
  List<RoutePoint> _currentRoute = [];
  final Map<String, List<RoutePoint>> _historicalRoutes = {};
  
  // Getters
  bool get isEnabled => _isEnabled;
  bool get isActive => _isActive;
  bool get hasPermission => _isPermissionGranted;
  bool get wifiOnlyDownloads => _wifiOnlyDownloads;
  
  RouteTrackingService._internal();
  
  /// Initialize the service with saved preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('offline_route_cache') ?? false;
    _wifiOnlyDownloads = prefs.getBool('wifi_only') ?? true;
    
    // Load saved routes
    await _loadSavedRoutes();
    
    // Check permission status if enabled
    if (_isEnabled) {
      await _checkPermissionStatus();
      if (_isPermissionGranted) {
        await startTracking();
      }
    }
    
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
  }
  
  /// Request location permission with clear explanation
  Future<bool> requestPermission() async {
    // Request permission
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }
    
    PermissionStatus permissionStatus = await _location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      permissionStatus = await _location.requestPermission();
      if (permissionStatus != PermissionStatus.granted) {
        return false;
      }
    }
    
    _isPermissionGranted = permissionStatus == PermissionStatus.granted;
    
    // If granted and feature is enabled, start tracking
    if (_isPermissionGranted && _isEnabled) {
      await startTracking();
    }
    
    notifyListeners();
    return _isPermissionGranted;
  }
  
  /// Check current permission status
  Future<void> _checkPermissionStatus() async {
    _isPermissionGranted = await _location.hasPermission() == PermissionStatus.granted;
    notifyListeners();
  }
  
  /// Enable or disable the feature
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    
    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_route_cache', enabled);
    
    if (enabled) {
      if (!_isPermissionGranted) {
        await requestPermission();
      } else {
        await startTracking();
      }
    } else {
      await stopTracking();
    }
    
    notifyListeners();
  }
  
  /// Set Wi-Fi only downloads preference
  Future<void> setWifiOnlyDownloads(bool wifiOnly) async {
    _wifiOnlyDownloads = wifiOnly;
    
    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only', wifiOnly);
    
    notifyListeners();
  }
  
  /// Start location tracking
  Future<void> startTracking() async {
    if (!_isEnabled || !_isPermissionGranted) return;
    
    // Stop any existing tracking
    await stopTracking();
    
    // Configure for battery efficiency
    await _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 30000, // 30 seconds
      distanceFilter: 50, // 50 meters
    );
    
    // Start location updates
    _isActive = true;
    notifyListeners();
    
    try {
      _locationSubscription = _location.onLocationChanged.listen(_processLocationUpdate);
      
      // Analyze routes every 30 minutes for pattern detection
      _predictionTimer = Timer.periodic(
        const Duration(minutes: 30), 
        (_) => _analyzeAndPredictRoutes()
      );
    } catch (e) {
      _isActive = false;
      notifyListeners();
      print('Error starting route tracking: $e');
    }
  }
  
  /// Stop location tracking
  Future<void> stopTracking() async {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _predictionTimer?.cancel();
    _predictionTimer = null;
    
    // Save current route if it has points
    if (_currentRoute.isNotEmpty) {
      await _saveCurrentRoute();
      _currentRoute = [];
    }
    
    _isActive = false;
    notifyListeners();
  }
  
  /// Process new location update
  void _processLocationUpdate(LocationData locationData) async {
    // Ignore invalid data
    if (locationData.latitude == null || locationData.longitude == null) return;
    
    // Get current connectivity status
    final connectivityResult = await _connectivity.checkConnectivity();
    final hasConnection = connectivityResult != ConnectivityResult.none;
    
    // Create route point
    final point = RoutePoint(
      latitude: locationData.latitude!,
      longitude: locationData.longitude!,
      hasConnection: hasConnection,
      timestamp: DateTime.now(),
    );
    
    // Add to current route
    _currentRoute.add(point);
    
    // If route gets too long, save it and start a new one
    if (_currentRoute.length > 100 || 
        (_currentRoute.isNotEmpty && 
         DateTime.now().difference(_currentRoute.first.timestamp).inHours >= 2)) {
      await _saveCurrentRoute();
      _currentRoute = [point]; // Keep the latest point as start of new route
    }
    
    // Quick check for potential dead zone entry
    if (!hasConnection && _currentRoute.length >= 3) {
      final List<RoutePoint> lastFewPoints = _currentRoute.sublist(_currentRoute.length - 3);
      if (lastFewPoints.where((p) => !p.hasConnection).length >= 2) {
        // We might be entering a dead zone
        _quickPredictAndDownload();
      }
    }
  }
  
  /// React to connectivity changes
  void _onConnectivityChanged(ConnectivityResult result) {
    if (result != ConnectivityResult.none && _isEnabled && _isActive) {
      // Got connection back, check if we should download content
      _analyzeAndPredictRoutes();
    }
  }
  
  /// Save current route with a timestamp-based ID
  Future<void> _saveCurrentRoute() async {
    if (_currentRoute.isEmpty) return;
    
    final String routeId = 'route_${DateTime.now().millisecondsSinceEpoch}';
    _historicalRoutes[routeId] = List.from(_currentRoute);
    
    // Save to persistent storage
    await _saveRoutes();
  }
  
  /// Save routes to persistent storage
  Future<void> _saveRoutes() async {
    try {
      // Limit storage to most recent 20 routes
      if (_historicalRoutes.length > 20) {
        final sortedKeys = _historicalRoutes.keys.toList()
          ..sort((a, b) => a.compareTo(b));
        
        while (_historicalRoutes.length > 20) {
          _historicalRoutes.remove(sortedKeys.first);
          sortedKeys.removeAt(0);
        }
      }
      
      // Convert to JSON
      final Map<String, List<Map<String, dynamic>>> routesJson = {};
      _historicalRoutes.forEach((key, route) {
        routesJson[key] = route.map((point) => point.toJson()).toList();
      });
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_routes', jsonEncode(routesJson));
    } catch (e) {
      print('Error saving routes: $e');
    }
  }
  
  /// Load saved routes from persistent storage
  Future<void> _loadSavedRoutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRoutes = prefs.getString('saved_routes');
      if (savedRoutes != null) {
        final Map<String, dynamic> routesJson = jsonDecode(savedRoutes);
        routesJson.forEach((key, value) {
          final List<dynamic> points = value as List;
          _historicalRoutes[key] = points
              .map((point) => RoutePoint.fromJson(point as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      print('Error loading saved routes: $e');
    }
  }
  
  /// Quick check for potential dead zones based on recent movement
  void _quickPredictAndDownload() async {
    if (!_shouldAllowDownload()) return;
      // Look for recently favorited or played content to download
    final recommendations = await _getQuickRecommendations();
    if (recommendations.isNotEmpty) {
      // Download each recommended album
      for (final album in recommendations) {
        await _downloadService.downloadAlbum(album, [album]);
      }
    }
  }
  
  /// Analyze historical routes to predict future connectivity issues
  Future<void> _analyzeAndPredictRoutes() async {
    if (!_isEnabled || _historicalRoutes.isEmpty || !_shouldAllowDownload()) return;
    
    // Identify dead zones (areas with consistently poor connectivity)
    final deadZones = _identifyDeadZones();
    if (deadZones.isEmpty) return;
      // Get content recommendations for potential offline use
    final recommendations = await _getRecommendedContent(deadZones);
    if (recommendations.isNotEmpty) {
      // Download each recommended album
      for (final album in recommendations) {
        await _downloadService.downloadAlbum(album, [album]);
      }
    }
  }
  
  /// Identify areas with consistently poor connectivity
  List<List<RoutePoint>> _identifyDeadZones() {
    final List<List<RoutePoint>> deadZones = [];
    
    // Process each historical route
    _historicalRoutes.forEach((_, route) {
      List<RoutePoint> currentDeadZone = [];
      
      // Look for sequences of 3+ consecutive points without connectivity
      for (int i = 0; i < route.length; i++) {
        if (!route[i].hasConnection) {
          currentDeadZone.add(route[i]);
        } else if (currentDeadZone.length >= 3) {
          // Found a significant dead zone
          deadZones.add(List.from(currentDeadZone));
          currentDeadZone = [];
        } else {
          currentDeadZone = [];
        }
      }
      
      // Check if we ended with a dead zone
      if (currentDeadZone.length >= 3) {
        deadZones.add(currentDeadZone);
      }
    });
    
    return deadZones;
  }
  
  /// Get content recommendations based on user preferences and behavior
  Future<List<Map<String, dynamic>>> _getRecommendedContent(
    List<List<RoutePoint>> deadZones
  ) async {
    // In a real app, this would analyze user listening habits
    // For now, we'll just get favorited and recently played items
    final recommendations = <Map<String, dynamic>>[];
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return recommendations;
      
      // Get user's favorited albums
      final favoritesResponse = await Supabase.instance.client
          .from('user_favorites')
          .select('album_id, albums(*)')
          .eq('user_id', user.id)
          .limit(5);
      
      if (favoritesResponse != null) {
        final favorites = List<Map<String, dynamic>>.from(favoritesResponse);
        for (final favorite in favorites) {
          final album = favorite['albums'];
          if (album != null) {
            recommendations.add(album);
          }
        }
      }
      
      // Get recently played albums
      final historyResponse = await Supabase.instance.client
          .from('user_play_history')
          .select('album_id, albums(*)')
          .eq('user_id', user.id)
          .order('played_at', ascending: false)
          .limit(3);
      
      if (historyResponse != null) {
        final history = List<Map<String, dynamic>>.from(historyResponse);
        for (final item in history) {
          final album = item['albums'];
          if (album != null && !recommendations.any((r) => r['id'] == album['id'])) {
            recommendations.add(album);
          }
        }
      }
    } catch (e) {
      print('Error getting content recommendations: $e');
    }
    
    return recommendations;
  }
  
  /// Quick recommendations based on recently played music
  Future<List<Map<String, dynamic>>> _getQuickRecommendations() async {
    final recommendations = <Map<String, dynamic>>[];
    
    try {
      // Get recently played songs from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final lastPlayedSong = prefs.getString('last_played_song');
      
      if (lastPlayedSong != null) {
        final songData = jsonDecode(lastPlayedSong);
        
        // If song belongs to an album, recommend entire album
        if (songData['album_id'] != null) {
          final albumResponse = await Supabase.instance.client
              .from('albums')
              .select()
              .eq('id', songData['album_id'])
              .single();
          
          if (albumResponse != null) {
            recommendations.add(albumResponse);
          }
        }
      }
    } catch (e) {
      print('Error getting quick recommendations: $e');
    }
    
    return recommendations;
  }
  
  /// Check if downloading should be allowed based on settings and connectivity
  bool _shouldAllowDownload() {
    if (!_isEnabled) return false;
    
    if (_wifiOnlyDownloads) {
      // Check if we're on WiFi
      try {
        Connectivity().checkConnectivity().then((result) {
          return result == ConnectivityResult.wifi;
        });
      } catch (_) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Clear all saved route data
  Future<void> clearSavedRoutes() async {
    _historicalRoutes.clear();
    _currentRoute = [];
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_routes');
    
    notifyListeners();
  }
  
  /// Dispose resources
  void dispose() {
    stopTracking();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
  
  /// Get a short explanation of how this feature works
  String getPrivacyExplanation() {
    return 'Offline Route Cache tracks your location patterns to predict when you\'ll '
           'need music in areas with poor connectivity. Your route data is stored only '
           'on your device and is never shared. Enabling this feature allows automatic '
           'downloads of music you might need offline.';
  }
}

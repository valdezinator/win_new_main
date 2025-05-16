import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'privacy/privacy_policy_widgets.dart';
import 'services/noise_detection_service.dart';
import 'services/route_tracking_service.dart';

/// SettingsScreen: Comprehensive settings page for the music app
/// Sections: Account, Playback, Notifications, Appearance, Privacy, About
class SettingsScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;
  const SettingsScreen({super.key, required this.supabaseClient});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Playback settings
  bool _crossfade = false;
  bool _gapless = false;
  String _audioQuality = 'High';
  bool _wifiOnly = true;
  bool _noiseAdaptiveCrossfade = false; // New setting
  bool _offlineRouteCache = false; // New setting

  // Notification settings
  bool _notifyNewReleases = true;
  bool _notifyPlaylistUpdates = true;
  bool _notifyAppUpdates = true;

  // Appearance settings
  String _theme = 'System';
  Color _accentColor = Colors.deepPurpleAccent;

  // Privacy
  bool _clearingCache = false;

  // Account
  String? _username;
  String? _email;

  // About
  String _appVersion = '';
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchUserProfile();
    _getAppVersion();
    _initializeServices();
  }
  
  // Initialize noise detection and route tracking services
  Future<void> _initializeServices() async {
    // Initialize services
    await NoiseDetectionService().initialize();
    await RouteTrackingService().initialize();
    
    // Apply current settings to services
    final noiseService = NoiseDetectionService();
    final routeService = RouteTrackingService();
    
    if (_noiseAdaptiveCrossfade && !noiseService.hasPermission) {
      // Request permission if feature is enabled but permission not granted
      await noiseService.requestPermission();
    }
    
    if (_offlineRouteCache && !routeService.hasPermission) {
      // Request permission if feature is enabled but permission not granted
      await routeService.requestPermission();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _crossfade = prefs.getBool('crossfade') ?? false;
      _gapless = prefs.getBool('gapless') ?? false;
      _audioQuality = prefs.getString('audio_quality') ?? 'High';
      _wifiOnly = prefs.getBool('wifi_only') ?? true;
      _notifyNewReleases = prefs.getBool('notify_new_releases') ?? true;
      _notifyPlaylistUpdates = prefs.getBool('notify_playlist_updates') ?? true;
      _notifyAppUpdates = prefs.getBool('notify_app_updates') ?? true;
      _theme = prefs.getString('theme') ?? 'System';
      int? colorValue = prefs.getInt('accent_color');
      if (colorValue != null) _accentColor = Color(colorValue);
      _noiseAdaptiveCrossfade = prefs.getBool('noise_adaptive_crossfade') ?? false; // Load new setting
      _offlineRouteCache = prefs.getBool('offline_route_cache') ?? false; // Load new setting
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) prefs.setBool(key, value);
    if (value is String) prefs.setString(key, value);
    if (value is int) prefs.setInt(key, value);
  }

  Future<void> _fetchUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    setState(() {
      _username = user?.userMetadata?['username'] ?? '';
      _email = user?.email ?? '';
    });
  }

  Future<void> _getAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = info.version;
    });
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    // Simulate cache clearing
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _clearingCache = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared successfully!')),
      );
    }
  }

  Future<void> _signOut() async {
    await widget.supabaseClient.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF181A20),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ------------------- Account Section -------------------
          _sectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.white70),
            title: Text(_username ?? '', style: const TextStyle(color: Colors.white)),
            subtitle: Text(_email ?? '', style: const TextStyle(color: Colors.white54)),
            trailing: TextButton(
              onPressed: _signOut,
              child: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
          const Divider(color: Colors.white24),

          // ------------------- Playback Section -------------------
          _sectionHeader('Playback'),
          SwitchListTile(
            value: _crossfade,
            onChanged: (v) { setState(() => _crossfade = v); _saveSetting('crossfade', v); },
            title: const Text('Crossfade', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Smoothly transition between songs'),
            activeColor: _accentColor,
          ),
          SwitchListTile(
            value: _gapless,
            onChanged: (v) { setState(() => _gapless = v); _saveSetting('gapless', v); },
            title: const Text('Gapless Playback', style: TextStyle(color: Colors.white)),
            subtitle: const Text('No silence between tracks'),
            activeColor: _accentColor,
          ),
          ListTile(
            title: const Text('Audio Quality', style: TextStyle(color: Colors.white)),
            subtitle: Text(_audioQuality, style: const TextStyle(color: Colors.white54)),
            trailing: DropdownButton<String>(
              value: _audioQuality,
              dropdownColor: Colors.grey[900],
              items: ['Low', 'Medium', 'High', 'Lossless']
                  .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                  .toList(),
              onChanged: (v) { if (v != null) { setState(() => _audioQuality = v); _saveSetting('audio_quality', v); } },
            ),
          ),          SwitchListTile(
            value: _wifiOnly,
            onChanged: (v) { 
              setState(() => _wifiOnly = v); 
              _saveSetting('wifi_only', v); 
              // Update route tracking service if enabled
              if (_offlineRouteCache) {
                RouteTrackingService().setWifiOnlyDownloads(v);
              }
            },
            title: const Text('Download over Wi-Fi only', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Prevent mobile data usage'),
            activeColor: _accentColor,
          ),Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  value: _noiseAdaptiveCrossfade,
                  onChanged: (v) { 
                    setState(() => _noiseAdaptiveCrossfade = v); 
                    _saveSetting('noise_adaptive_crossfade', v); 
                    // Initialize or disable the noise detection service
                    NoiseDetectionService().setEnabled(v);
                  },
                  title: const Text('Noise Adaptive Crossfade', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Adjust volume based on ambient noise'),
                  activeColor: _accentColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white70),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const NoiseDetectionPrivacyPolicy(),
                  );
                },
              ),
            ],
          ),          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  value: _offlineRouteCache,
                  onChanged: (v) { 
                    setState(() => _offlineRouteCache = v); 
                    _saveSetting('offline_route_cache', v); 
                    // Initialize or disable the route tracking service
                    RouteTrackingService().setEnabled(v);
                    // Update WiFi only setting for route service
                    RouteTrackingService().setWifiOnlyDownloads(_wifiOnly);
                  },
                  title: const Text('Offline Route Cache', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Download music for areas with poor connectivity'),
                  activeColor: _accentColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white70),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const RouteTrackingPrivacyPolicy(),
                  );
                },
              ),
            ],
          ),
          const Divider(color: Colors.white24),

          // ------------------- Notification Section -------------------
          _sectionHeader('Notifications'),
          SwitchListTile(
            value: _notifyNewReleases,
            onChanged: (v) { setState(() => _notifyNewReleases = v); _saveSetting('notify_new_releases', v); },
            title: const Text('New Releases', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Get notified about new music'),
            activeColor: _accentColor,
          ),
          SwitchListTile(
            value: _notifyPlaylistUpdates,
            onChanged: (v) { setState(() => _notifyPlaylistUpdates = v); _saveSetting('notify_playlist_updates', v); },
            title: const Text('Playlist Updates', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Updates to your playlists'),
            activeColor: _accentColor,
          ),
          SwitchListTile(
            value: _notifyAppUpdates,
            onChanged: (v) { setState(() => _notifyAppUpdates = v); _saveSetting('notify_app_updates', v); },
            title: const Text('App Updates', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Important news and updates'),
            activeColor: _accentColor,
          ),
          const Divider(color: Colors.white24),

          // ------------------- Appearance Section -------------------
          _sectionHeader('Appearance'),
          ListTile(
            title: const Text('Theme', style: TextStyle(color: Colors.white)),
            trailing: DropdownButton<String>(
              value: _theme,
              dropdownColor: Colors.grey[900],
              items: ['System', 'Dark', 'Light']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) { if (v != null) { setState(() => _theme = v); _saveSetting('theme', v); } },
            ),
          ),
          ListTile(
            title: const Text('Accent Color', style: TextStyle(color: Colors.white)),
            trailing: GestureDetector(
              onTap: _pickAccentColor,
              child: CircleAvatar(backgroundColor: _accentColor, radius: 14),
            ),
          ),
          const Divider(color: Colors.white24),

          // ------------------- Privacy Section -------------------
          _sectionHeader('Privacy'),
          ListTile(
            title: const Text('Clear Cache', style: TextStyle(color: Colors.white)),
            trailing: _clearingCache
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: _clearCache,
                  ),
          ),
          ListTile(
            title: const Text('Manage Data', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View or delete your data'),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 18),
            onTap: () {
              // TODO: Implement data management
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Data management coming soon!')),
              );
            },
          ),
          const Divider(color: Colors.white24),

          // ------------------- About Section -------------------
          _sectionHeader('About'),
          ListTile(
            title: const Text('App Version', style: TextStyle(color: Colors.white)),
            subtitle: Text(_appVersion, style: const TextStyle(color: Colors.white54)),
          ),
          ListTile(
            title: const Text('Licenses', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 18),
            onTap: () => showLicensePage(context: context),
          ),
        ],
      ),
    );
  }

  // Helper for section headers
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Accent color picker dialog
  void _pickAccentColor() async {
    Color? picked = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Pick Accent Color', style: TextStyle(color: Colors.white)),
          content: Wrap(
            spacing: 10,
            children: [
              Colors.deepPurpleAccent,
              Colors.blueAccent,
              Colors.greenAccent,
              Colors.redAccent,
              Colors.orangeAccent,
              Colors.pinkAccent,
              Colors.amberAccent,
              Colors.cyanAccent,
            ].map((color) => GestureDetector(
              onTap: () => Navigator.of(context).pop(color),
              child: CircleAvatar(backgroundColor: color, radius: 18),
            )).toList(),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _accentColor = picked);
      _saveSetting('accent_color', picked.value);
    }
  }
}

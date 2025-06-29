import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import 'privacy/privacy_policy_widgets.dart';
import 'services/noise_detection_service.dart';
import 'services/route_tracking_service.dart';
import 'services/payment_service.dart';
import 'services/auth_service.dart';
import 'widgets/subscription_manager.dart';

/// SettingsScreen: Comprehensive settings page for the music app
/// Redesigned to match Spotify Desktop layout with sidebar navigation
class SettingsScreen extends StatefulWidget {
  final SupabaseClient supabaseClient;
  const SettingsScreen({super.key, required this.supabaseClient});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Navigation
  int _selectedIndex = 0;
  
  // Playback settings
  bool _crossfade = false;
  bool _gapless = false;
  bool _wifiOnly = true;
  bool _noiseAdaptiveCrossfade = false;
  bool _offlineRouteCache = false;

  // Notification settings
  bool _notifyNewReleases = true;
  bool _notifyPlaylistUpdates = true;
  bool _notifyAppUpdates = true;

  // Privacy
  bool _clearingCache = false;

  // Account
  String? _username;
  
  // Payment service
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();
  String? _email;

  // About
  String _appVersion = '';

  // Navigation items
  final List<Map<String, dynamic>> _navigationItems = [
    {'title': 'Account', 'icon': Icons.person_outline},
    {'title': 'Playback', 'icon': Icons.play_circle_outline},
    {'title': 'Notifications', 'icon': Icons.notifications_outlined},
    {'title': 'Appearance', 'icon': Icons.palette_outlined},
    {'title': 'Privacy', 'icon': Icons.security_outlined},
    {'title': 'About', 'icon': Icons.info_outline},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchUserProfile();
    _getAppVersion();
    _initializeServices();
    _initPaymentService();
  }
  
  // Initialize payment service
  Future<void> _initPaymentService() async {
    await _paymentService.initialize();
    if (mounted) setState(() {});
  }
  
  // Open Premium Plans webpage in default browser
  Future<void> _openPremiumPlans() async {
    final Uri url = Uri.parse('file://${Platform.isWindows ? '/' : ''}${Directory.current.path}/assets/premium_plans.html');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Premium Plans page')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }
  
  // Initialize noise detection and route tracking services
  Future<void> _initializeServices() async {
    await NoiseDetectionService().initialize();
    await RouteTrackingService().initialize();
    
    final noiseService = NoiseDetectionService();
    final routeService = RouteTrackingService();
    
    if (_noiseAdaptiveCrossfade && !noiseService.hasPermission) {
      await noiseService.requestPermission();
    }
    
    if (_offlineRouteCache && !routeService.hasPermission) {
      await routeService.requestPermission();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _crossfade = prefs.getBool('crossfade') ?? false;
      _gapless = prefs.getBool('gapless') ?? false;
      _wifiOnly = prefs.getBool('wifi_only') ?? true;
      _notifyNewReleases = prefs.getBool('notify_new_releases') ?? true;
      _notifyPlaylistUpdates = prefs.getBool('notify_playlist_updates') ?? true;
      _notifyAppUpdates = prefs.getBool('notify_app_updates') ?? true;
      _noiseAdaptiveCrossfade = prefs.getBool('noise_adaptive_crossfade') ?? false;
      _offlineRouteCache = prefs.getBool('offline_route_cache') ?? false;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) prefs.setBool(key, value);
    if (value is String) prefs.setString(key, value);
    if (value is int) prefs.setInt(key, value);
  }

  Future<void> _fetchUserProfile() async {
    setState(() {
      _username = _authService.username;
      _email = _authService.email;
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
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _clearingCache = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared successfully!')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed out successfully'),
            backgroundColor: Color(0xFF1DB954),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Row(
        children: [
          // Sidebar Navigation
          Container(
            width: 280,
            color: const Color(0xFF000000),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Navigation Items
                Expanded(
                  child: ListView.builder(
                    itemCount: _navigationItems.length,
                    itemBuilder: (context, index) {
                      final item = _navigationItems[index];
                      final isSelected = _selectedIndex == index;
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF282828) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          leading: Icon(
                            item['icon'],
                            color: isSelected ? Colors.white : Colors.white70,
                            size: 24,
                          ),
                          title: Text(
                            item['title'],
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 16,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          onTap: () => setState(() => _selectedIndex = index),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Main Content Area
          Expanded(
            child: Container(
              color: const Color(0xFF121212),
              child: _buildContentArea(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    switch (_selectedIndex) {
      case 0:
        return _buildAccountSection();
      case 1:
        return _buildPlaybackSection();
      case 2:
        return _buildNotificationsSection();
      case 3:
        return _buildAppearanceSection();
      case 4:
        return _buildPrivacySection();
      case 5:
        return _buildAboutSection();
      default:
        return _buildAccountSection();
    }
  }

  Widget _buildAccountSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Account'),
          const SizedBox(height: 24),
          
          // User Profile Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFF1DB954),
                  child: Text(
                    (_username?.isNotEmpty == true ? _username![0].toUpperCase() : 'U'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _username ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _email ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _signOut,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          _buildSectionHeader('Subscription'),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const SubscriptionManager(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Playback'),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildSwitchTile(
                  'Crossfade',
                  'Smoothly transition between songs',
                  _crossfade,
                  (value) {
                    setState(() => _crossfade = value);
                    _saveSetting('crossfade', value);
                  },
                ),
                _buildDivider(),
                _buildSwitchTile(
                  'Gapless Playback',
                  'No silence between tracks',
                  _gapless,
                  (value) {
                    setState(() => _gapless = value);
                    _saveSetting('gapless', value);
                  },
                ),
                _buildDivider(),
                _buildSwitchTile(
                  'Download over Wi-Fi only',
                  'Prevent mobile data usage',
                  _wifiOnly,
                  (value) {
                    setState(() => _wifiOnly = value);
                    _saveSetting('wifi_only', value);
                    if (_offlineRouteCache) {
                      RouteTrackingService().setWifiOnlyDownloads(value);
                    }
                  },
                ),
                _buildDivider(),
                _buildSwitchTileWithInfo(
                  'Noise Adaptive Crossfade',
                  'Adjust volume based on ambient noise',
                  _noiseAdaptiveCrossfade,
                  (value) {
                    setState(() => _noiseAdaptiveCrossfade = value);
                    _saveSetting('noise_adaptive_crossfade', value);
                    NoiseDetectionService().setEnabled(value);
                  },
                  () => showDialog(
                    context: context,
                    builder: (context) => const NoiseDetectionPrivacyPolicy(),
                  ),
                ),
                _buildDivider(),
                _buildSwitchTileWithInfo(
                  'Offline Route Cache',
                  'Download music for areas with poor connectivity',
                  _offlineRouteCache,
                  (value) {
                    setState(() => _offlineRouteCache = value);
                    _saveSetting('offline_route_cache', value);
                    RouteTrackingService().setEnabled(value);
                    RouteTrackingService().setWifiOnlyDownloads(_wifiOnly);
                  },
                  () => showDialog(
                    context: context,
                    builder: (context) => const RouteTrackingPrivacyPolicy(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Notifications'),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildSwitchTile(
                  'New Releases',
                  'Get notified about new music',
                  _notifyNewReleases,
                  (value) {
                    setState(() => _notifyNewReleases = value);
                    _saveSetting('notify_new_releases', value);
                  },
                ),
                _buildDivider(),
                _buildSwitchTile(
                  'Playlist Updates',
                  'Updates to your playlists',
                  _notifyPlaylistUpdates,
                  (value) {
                    setState(() => _notifyPlaylistUpdates = value);
                    _saveSetting('notify_playlist_updates', value);
                  },
                ),
                _buildDivider(),
                _buildSwitchTile(
                  'App Updates',
                  'Important news and updates',
                  _notifyAppUpdates,
                  (value) {
                    setState(() => _notifyAppUpdates = value);
                    _saveSetting('notify_app_updates', value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Appearance'),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildListTile(
                  'Accent Color',
                  'Customize the app\'s accent color',
                  Icons.palette_outlined,
                  onTap: _pickAccentColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Privacy'),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildListTile(
                  'Clear Cache',
                  'Free up storage space',
                  Icons.delete_outline,
                  trailing: _clearingCache
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _clearCache,
                ),
                _buildDivider(),
                _buildListTile(
                  'Manage Data',
                  'View or delete your data',
                  Icons.data_usage_outlined,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data management coming soon!')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('About'),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildListTile(
                  'App Version',
                  _appVersion,
                  Icons.info_outline,
                ),
                _buildDivider(),
                _buildListTile(
                  'Licenses',
                  'View third-party licenses',
                  Icons.description_outlined,
                  onTap: () => showLicensePage(context: context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF1DB954),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTileWithInfo(String title, String subtitle, bool value, ValueChanged<bool> onChanged, VoidCallback onInfoTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white70, size: 20),
            onPressed: onInfoTap,
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF1DB954),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile(String title, String subtitle, IconData icon, {Widget? trailing, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (onTap != null) const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: Color(0xFF404040), height: 1),
    );
  }

  // Accent color picker dialog
  void _pickAccentColor() async {
    Color? picked = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
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
      _saveSetting('accent_color', picked.value);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Define AudioQuality enum for consistent usage
enum AudioQuality {
  low('Low'),
  medium('Medium'),
  high('High'),
  lossless('Lossless');

  final String label;
  const AudioQuality(this.label);

  static AudioQuality fromString(String value) {
    return AudioQuality.values.firstWhere(
      (quality) => quality.label.toLowerCase() == value.toLowerCase(),
      orElse: () => AudioQuality.high,
    );
  }
}

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
  AudioQuality _audioQuality = AudioQuality.high;
  bool _wifiOnly = true;

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
  }
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _crossfade = prefs.getBool('crossfade') ?? false;
      _gapless = prefs.getBool('gapless') ?? false;
      _audioQuality = AudioQuality.fromString(prefs.getString('audio_quality') ?? 'High');
      _wifiOnly = prefs.getBool('wifi_only') ?? true;
      _notifyNewReleases = prefs.getBool('notify_new_releases') ?? true;
      _notifyPlaylistUpdates = prefs.getBool('notify_playlist_updates') ?? true;
      _notifyAppUpdates = prefs.getBool('notify_app_updates') ?? true;
      _theme = prefs.getString('theme') ?? 'System';
      int? colorValue = prefs.getInt('accent_color');
      if (colorValue != null) _accentColor = Color(colorValue);
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
        title: const Text('Settings',
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w300)  ),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Determine if we have enough width for a multi-column layout
          final bool isWideScreen = constraints.maxWidth > 900;

          if (isWideScreen) {
            // Desktop multi-column layout
            return _buildDesktopLayout();
          } else {
            // Single column layout for narrower windows
            return _buildMobileLayout();
          }
        },
      ),
    );
  }

  // Desktop layout with multiple columns
  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column - Account and Playback
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionCard(
                  'Account',
                  [
                    ListTile(
                      leading: const Icon(Icons.person, color: Colors.white70, size: 28),
                      title: Text(_username ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: Text(_email ?? '',
                        style: const TextStyle(color: Colors.white54, fontSize: 14)),
                      trailing: TextButton(
                        onPressed: _signOut,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: const Text('Sign out',
                          style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  'Playback',
                  [
                    SwitchListTile(
                      value: _crossfade,
                      onChanged: (v) { setState(() => _crossfade = v); _saveSetting('crossfade', v); },
                      title: const Text('Crossfade',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('Smoothly transition between songs',
                        style: TextStyle(fontSize: 14)),
                      activeColor: _accentColor,
                    ),
                    SwitchListTile(
                      value: _gapless,
                      onChanged: (v) { setState(() => _gapless = v); _saveSetting('gapless', v); },
                      title: const Text('Gapless Playback',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('No silence between tracks',
                        style: TextStyle(fontSize: 14)),
                      activeColor: _accentColor,
                    ),
                    ListTile(
                      title: const Text('Audio Quality',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: Text(_audioQuality.label,
                        style: const TextStyle(color: Colors.white54, fontSize: 14)),
                      trailing: DropdownButton<AudioQuality>(
                        value: _audioQuality,
                        dropdownColor: Colors.grey[900],
                        items: AudioQuality.values
                            .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _audioQuality = v);
                            _saveSetting('audio_quality', v.label);
                          }
                        },
                      ),
                    ),
                    SwitchListTile(
                      value: _wifiOnly,
                      onChanged: (v) { setState(() => _wifiOnly = v); _saveSetting('wifi_only', v); },
                      title: const Text('Download over Wi-Fi only',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('Prevent mobile data usage',
                        style: TextStyle(fontSize: 14)),
                      activeColor: _accentColor,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // Middle column - Notifications and Appearance
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionCard(
                  'Notifications',
                  [
                    SwitchListTile(
                      value: _notifyNewReleases,
                      onChanged: (v) { setState(() => _notifyNewReleases = v); _saveSetting('notify_new_releases', v); },
                      title: const Text('New Releases',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('Get notified about new music',
                        style: TextStyle(fontSize: 14)),
                      activeColor: _accentColor,
                    ),
                    SwitchListTile(
                      value: _notifyPlaylistUpdates,
                      onChanged: (v) { setState(() => _notifyPlaylistUpdates = v); _saveSetting('notify_playlist_updates', v); },
                      title: const Text('Playlist Updates',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('Updates to your playlists',
                        style: TextStyle(fontSize: 14)),
                      activeColor: _accentColor,
                    ),
                    SwitchListTile(
                      value: _notifyAppUpdates,
                      onChanged: (v) { setState(() => _notifyAppUpdates = v); _saveSetting('notify_app_updates', v); },
                      title: const Text('App Updates',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('Important news and updates',
                        style: TextStyle(fontSize: 14)),
                      activeColor: _accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  'Appearance',
                  [
                    ListTile(
                      title: const Text('Theme',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
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
                      title: const Text('Accent Color',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      trailing: GestureDetector(
                        onTap: _pickAccentColor,
                        child: CircleAvatar(backgroundColor: _accentColor, radius: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // Right column - Privacy and About
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionCard(
                  'Privacy',
                  [
                    ListTile(
                      title: const Text('Clear Cache',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      trailing: _clearingCache
                          ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 24),
                              onPressed: _clearCache,
                            ),
                    ),
                    ListTile(
                      title: const Text('Manage Data',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: const Text('View or delete your data',
                        style: TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 18),
                      onTap: () {
                        // TODO: Implement data management
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Data management coming soon!')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  'About',
                  [
                    ListTile(
                      title: const Text('App Version',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: Text(_appVersion,
                        style: const TextStyle(color: Colors.white54, fontSize: 14)),
                    ),
                    ListTile(
                      title: const Text('Licenses',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 18),
                      onTap: () => showLicensePage(context: context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Mobile layout with single column
  Widget _buildMobileLayout() {
    return ListView(
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
          subtitle: Text(_audioQuality.label, style: const TextStyle(color: Colors.white54)),
          trailing: DropdownButton<AudioQuality>(
            value: _audioQuality,
            dropdownColor: Colors.grey[900],
            items: AudioQuality.values
                .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _audioQuality = v);
                _saveSetting('audio_quality', v.label);
              }
            },
          ),
        ),
        SwitchListTile(
          value: _wifiOnly,
          onChanged: (v) { setState(() => _wifiOnly = v); _saveSetting('wifi_only', v); },
          title: const Text('Download over Wi-Fi only', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Prevent mobile data usage'),
          activeColor: _accentColor,
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
    );
  }

  // Helper for creating section cards in desktop layout
  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      color: Colors.black.withOpacity(0.3),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 16.0),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...children,
          ],
        ),
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

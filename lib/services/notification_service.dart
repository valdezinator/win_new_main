import 'package:win_toast/win_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      await WinToast.instance().initialize(
        aumId: 'com.resonance.app',
        displayName: 'Resonance',
        iconPath: 'C:/Users/shrey/OneDrive/Documents/win_new_main/windows/runner/resources/app_icon.ico', // <-- Update this path to your .ico file
      );
      _initialized = true;
    }
  }

  Future<bool> _isEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true;
  }

  Future<void> showNewReleaseNotification(String title, String body) async {
    if (await _isEnabled('notify_new_releases')) {
      await _showToast(title: title, body: body);
    }
  }

  Future<void> showPlaylistUpdateNotification(String title, String body) async {
    if (await _isEnabled('notify_playlist_updates')) {
      await _showToast(title: title, body: body);
    }
  }

  Future<void> showAppUpdateNotification(String title, String body) async {
    if (await _isEnabled('notify_app_updates')) {
      await _showToast(title: title, body: body);
    }
  }

  Future<void> showTestNotification(String type) async {
    switch (type) {
      case 'new_release':
        await showNewReleaseNotification('New Release!', 'Check out the latest music now.');
        break;
      case 'playlist_update':
        await showPlaylistUpdateNotification('Playlist Updated!', 'Your playlist has new tracks.');
        break;
      case 'app_update':
        await showAppUpdateNotification('App Update!', 'Important news and updates.');
        break;
    }
  }

  Future<void> _showToast({required String title, required String body}) async {
    await initialize();
    final xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$title</text>
      <text>$body</text>
    </binding>
  </visual>
</toast>
''';
    await WinToast.instance().showCustomToast(xml: xml);
  }
} 
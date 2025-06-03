import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CustomWindowListener extends WindowListener {
  final bool minimizeToTray;

  CustomWindowListener({required this.minimizeToTray});

  @override
  void onWindowClose() async {
    if (minimizeToTray) {
      await windowManager.hide();
    } else {
      exit(0);
    }
  }
}

class StartupService {
  static final StartupService _instance = StartupService._internal();
  factory StartupService() => _instance;

  bool _isInitialized = false;
  static const String _startupKey = 'start_with_system';
  static const String _minimizeToTrayKey = 'minimize_to_tray';
  late CustomWindowListener _windowListener;

  StartupService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await _initializeStartupOptions();
    }

    _isInitialized = true;
  }

  Future<void> _initializeStartupOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final startWithSystem = prefs.getBool(_startupKey) ?? false;
    final minimizeToTray = prefs.getBool(_minimizeToTrayKey) ?? true;

    if (startWithSystem) {
      await _setStartupEnabled(true);
    }

    // Set window close behavior based on minimize to tray setting
    _windowListener = CustomWindowListener(minimizeToTray: minimizeToTray);
    windowManager.addListener(_windowListener);
  }

  Future<void> setStartWithSystem(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startupKey, enabled);
    await _setStartupEnabled(enabled);
  }

  Future<void> setMinimizeToTray(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeToTrayKey, enabled);
  }

  Future<bool> isStartWithSystemEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_startupKey) ?? false;
  }

  Future<bool> isMinimizeToTrayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_minimizeToTrayKey) ?? true;
  }

  Future<void> _setStartupEnabled(bool enabled) async {
    if (Platform.isWindows) {
      await _setWindowsStartup(enabled);
    } else if (Platform.isMacOS) {
      await _setMacOSStartup(enabled);
    } else if (Platform.isLinux) {
      await _setLinuxStartup(enabled);
    }
  }

  Future<void> _setWindowsStartup(bool enabled) async {
    final appData = await getApplicationSupportDirectory();
    final startupScript = path.join(appData.path, 'startup.vbs');
    
    if (enabled) {
      // Create VBS script to start the app
      final script = '''
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "${Platform.resolvedExecutable}", 0, False
''';
      await File(startupScript).writeAsString(script);
      
      // Add to Windows startup
      final startupFolder = path.join(
        Platform.environment['APPDATA']!,
        'Microsoft\\Windows\\Start Menu\\Programs\\Startup'
      );
      final shortcutPath = path.join(startupFolder, 'Cresca.lnk');
      
      // Create shortcut
      final shortcut = '''
Set WshShell = CreateObject("WScript.Shell")
Set Shortcut = WshShell.CreateShortcut("$shortcutPath")
Shortcut.TargetPath = "${Platform.resolvedExecutable}"
Shortcut.WorkingDirectory = "${path.dirname(Platform.resolvedExecutable)}"
Shortcut.Save
''';
      await File(path.join(appData.path, 'create_shortcut.vbs')).writeAsString(shortcut);
      await Process.run('wscript', [path.join(appData.path, 'create_shortcut.vbs')]);
    } else {
      // Remove from Windows startup
      final startupFolder = path.join(
        Platform.environment['APPDATA']!,
        'Microsoft\\Windows\\Start Menu\\Programs\\Startup'
      );
      final shortcutPath = path.join(startupFolder, 'Cresca.lnk');
      if (await File(shortcutPath).exists()) {
        await File(shortcutPath).delete();
      }
    }
  }

  Future<void> _setMacOSStartup(bool enabled) async {
    final appData = await getApplicationSupportDirectory();
    final plistPath = path.join(
      Platform.environment['HOME']!,
      'Library/LaunchAgents/com.cresca.app.plist'
    );
    
    if (enabled) {
      // Create LaunchAgent plist
      final plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cresca.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>${Platform.resolvedExecutable}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>''';
      await File(plistPath).writeAsString(plist);
    } else {
      // Remove LaunchAgent plist
      if (await File(plistPath).exists()) {
        await File(plistPath).delete();
      }
    }
  }

  Future<void> _setLinuxStartup(bool enabled) async {
    final appData = await getApplicationSupportDirectory();
    final desktopFile = path.join(
      Platform.environment['HOME']!,
      '.config/autostart/cresca.desktop'
    );
    
    if (enabled) {
      // Create desktop entry
      final entry = '''[Desktop Entry]
Type=Application
Name=Cresca
Exec=${Platform.resolvedExecutable}
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
''';
      await File(desktopFile).writeAsString(entry);
    } else {
      // Remove desktop entry
      if (await File(desktopFile).exists()) {
        await File(desktopFile).delete();
      }
    }
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;
    windowManager.removeListener(_windowListener);
    _isInitialized = false;
  }
} 
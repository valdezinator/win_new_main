import 'package:flutter/material.dart';

class CurrentSongProvider extends InheritedWidget {
  final Map<String, dynamic>? currentSong;

  const CurrentSongProvider({
    super.key,
    required this.currentSong,
    required Widget child,
  }) : super(child: child);

  static CurrentSongProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CurrentSongProvider>();
  }

  @override
  bool updateShouldNotify(CurrentSongProvider oldWidget) {
    return currentSong?.toString() != oldWidget.currentSong?.toString();
  }
}

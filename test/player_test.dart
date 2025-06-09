import 'package:flutter_test/flutter_test.dart';
import 'package:your_app_name/player/player.dart';
import 'package:your_app_name/player/player_state.dart';

void main() {
  group('Player Tests', () {
    late Player player;

    setUp(() {
      player = Player();
    });

    test('Initial state should be stopped', () {
      expect(player.state, equals(PlayerState.stopped));
    });

    test('Play should change state to playing', () async {
      await player.play();
      expect(player.state, equals(PlayerState.playing));
    });

    test('Pause should change state to paused', () async {
      await player.play();
      await player.pause();
      expect(player.state, equals(PlayerState.paused));
    });

    test('Stop should change state to stopped', () async {
      await player.play();
      await player.stop();
      expect(player.state, equals(PlayerState.stopped));
    });

    test('Seek should update position', () async {
      const testPosition = Duration(seconds: 30);
      await player.seek(testPosition);
      expect(player.position, equals(testPosition));
    });

    test('Volume should be between 0 and 1', () {
      expect(() => player.setVolume(1.5), throwsAssertionError);
      expect(() => player.setVolume(-0.5), throwsAssertionError);
      player.setVolume(0.5);
      expect(player.volume, equals(0.5));
    });
  });
} 
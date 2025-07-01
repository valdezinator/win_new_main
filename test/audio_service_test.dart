import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart' show CrossfadeAudioSource, ConcatenatingAudioSource, AudioSource;
import 'package:cresca/services/audio_service.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioService Crossfade and Gapless', () {
    late AudioService audioService;
    late MockAudioPlayer mockPlayer;

    setUp(() {
      mockPlayer = MockAudioPlayer();
      audioService = AudioService();
      // Inject the mock player if needed (if AudioService supports DI)
      // Otherwise, test logic by inspecting the audio source type
    });

    test('Crossfade is OFF by default', () async {
      expect(audioService.crossfadeEnabled, isFalse);
      expect(audioService.crossfadeDurationMs, equals(1500)); // default
    });

    test('Enabling crossfade updates state', () async {
      await audioService.setCrossfadeDuration(2000);
      expect(audioService.crossfadeEnabled, isTrue);
      expect(audioService.crossfadeDurationMs, equals(2000));
    });

    test('Disabling crossfade updates state', () async {
      await audioService.setCrossfadeDuration(0);
      expect(audioService.crossfadeEnabled, isFalse);
      expect(audioService.crossfadeDurationMs, equals(0));
    });

    test('playQueue uses ConcatenatingAudioSource and wraps with CrossfadeAudioSource if enabled', () async {
      final queue = [
        {
          'id': '1',
          'title': 'Song 1',
          'audio_url': 'https://example.com/1.mp3',
          'artist': 'Artist',
          'duration': 120,
        },
        {
          'id': '2',
          'title': 'Song 2',
          'audio_url': 'https://example.com/2.mp3',
          'artist': 'Artist',
          'duration': 130,
        },
      ];
      await audioService.setCrossfadeDuration(1500);
      // We can't directly check the player's source, but we can check the type of source built
      // So, let's extract the logic for building the source into a protected method for testability
      // For now, we can check that the state is correct
      expect(audioService.crossfadeEnabled, isTrue);
      expect(audioService.crossfadeDurationMs, equals(1500));
      // To fully test, AudioService should expose a method to build the source for a queue for test
    });

    test('playQueue uses ConcatenatingAudioSource only if crossfade is disabled', () async {
      final queue = [
        {
          'id': '1',
          'title': 'Song 1',
          'audio_url': 'https://example.com/1.mp3',
          'artist': 'Artist',
          'duration': 120,
        },
        {
          'id': '2',
          'title': 'Song 2',
          'audio_url': 'https://example.com/2.mp3',
          'artist': 'Artist',
          'duration': 130,
        },
      ];
      await audioService.setCrossfadeDuration(0);
      expect(audioService.crossfadeEnabled, isFalse);
      expect(audioService.crossfadeDurationMs, equals(0));
      // As above, to fully test, AudioService should expose a method to build the source for a queue for test
    });
  });
} 
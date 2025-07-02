# Spotify-like Ad Implementation Guide

This document explains the **Spotify-like ad logic** implemented in this codebase. Use this as a reference for implementing similar ad logic in another codebase (e.g., a mobile app).

---

## 1. **Ad Logic Overview**

- **Ads only play after a set amount of active listening time** (e.g., 10 minutes).
- **Active listening time** is counted only when music is actually playing (not paused/stopped).
- **Ads play at song boundaries** (before the next song starts), never in the middle of a song.
- **Ad timer pauses/resumes with playback.**
- **If the user skips a song and the timer is up, an ad plays before the next song.**
- **Premium users are excluded** (add a check for this in your implementation).

---

## 2. **Key Components & Responsibilities**

### **AdManagerService**
- Tracks active listening time.
- Determines when an ad is due.
- Plays ads and resets the timer after an ad.
- Exposes methods to notify it of playback state changes.

### **AudioService** (or your main audio player controller)
- Notifies AdManagerService when playback starts, pauses, stops, or a song finishes.
- Checks with AdManagerService before playing a new song; if an ad is due, plays the ad first.

---

## 3. **Core Ad Logic (Pseudocode/Code)**

### **AdManagerService**
```dart
class AdManagerService {
  static const int AD_INTERVAL_MINUTES = 10; // Ad interval
  Duration _activeListeningTime = Duration.zero;
  DateTime? _lastPlaybackStart;
  bool _adDue = false;
  bool _isAdPlaying = false;

  // Call when playback starts
  void onPlaybackStarted() {
    _lastPlaybackStart = DateTime.now();
  }

  // Call when playback pauses or stops
  void onPlaybackPaused() {
    if (_lastPlaybackStart != null) {
      final now = DateTime.now();
      _activeListeningTime += now.difference(_lastPlaybackStart!);
      _lastPlaybackStart = null;
      if (_activeListeningTime.inMinutes >= AD_INTERVAL_MINUTES) {
        _adDue = true;
      }
    }
  }

  // Call when a song finishes
  void onSongFinished() {
    onPlaybackPaused();
  }

  // Check before playing a new song
  bool shouldPlayAdBeforeNextSong() {
    return _adDue && !_isAdPlaying;
  }

  // Call after ad is played
  void resetAdDue() {
    _adDue = false;
    _activeListeningTime = Duration.zero;
  }

  // ... (ad playback logic, skip logic, etc.) ...
}
```

### **AudioService** (Main Player Controller)
```dart
Future<void> playSong(Map<String, dynamic> song) async {
  final adManager = AdManagerService();
  if (adManager.shouldPlayAdBeforeNextSong()) {
    await adManager.playAd();
    adManager.resetAdDue();
  }
  adManager.onPlaybackStarted();
  // ... play the song ...
}

Future<void> pause() async {
  await player.pause();
  AdManagerService().onPlaybackPaused();
}

Future<void> stop() async {
  await player.stop();
  AdManagerService().onPlaybackPaused();
}

void onSongFinished() {
  AdManagerService().onSongFinished();
}
```

---

## 4. **Ad Playback Logic**
- When `playAd()` is called, pause the main player, play the ad audio, and after the ad, resume the original song (if it was playing before the ad).
- Track whether the song was playing or paused before the ad, and only resume if it was playing.

**Example:**
```dart
Future<void> playAd() async {
  // Store current song info and pause main player
  _wasPlayingBeforeAd = _mainAudioPlayer!.playing;
  await _mainAudioPlayer!.pause();
  // ... play ad audio ...
  // After ad:
  if (_wasPlayingBeforeAd) {
    _mainAudioPlayer!.play();
  }
}
```

---

## 5. **Integration Points**
- **Playback Start:** Call `onPlaybackStarted()` when playback starts.
- **Playback Pause/Stop:** Call `onPlaybackPaused()` when playback pauses or stops.
- **Song Finish:** Call `onSongFinished()` when a song finishes.
- **Before Playing a New Song:** Check `shouldPlayAdBeforeNextSong()` and play ad if needed.
- **After Ad:** Call `resetAdDue()`.

---

## 6. **Premium User Exclusion (Recommended)**
- Add a check for premium users before running any ad logic:
```dart
if (isPremiumUser) {
  // Play song directly, skip ad logic
} else {
  // Run ad logic as above
}
```

---

## 7. **UI/UX Recommendations**
- Show a clear "Ad" or "Sponsored" label when an ad is playing.
- Optionally, show a countdown or progress bar for the ad.
- Disable skip/next during ad playback if required.

---

## 8. **Testing Checklist**
- [ ] Ads only play after 10 minutes of active listening.
- [ ] Timer pauses/resumes with playback.
- [ ] Ads play at song boundaries, never in the middle.
- [ ] Skipping songs triggers ad if timer is up.
- [ ] Premium users never get ads (if implemented).
- [ ] UI clearly indicates when an ad is playing.

---

## 9. **Extending/Customizing**
- Change `AD_INTERVAL_MINUTES` for a different ad frequency.
- Integrate with your analytics for ad impressions.
- Add support for different ad types (audio, video, banners, etc.).

---

## 10. **Summary**
This guide provides a robust, Spotify-like ad experience for free users. Integrate the above logic into your mobile or other codebases for a seamless, user-friendly ad system. 
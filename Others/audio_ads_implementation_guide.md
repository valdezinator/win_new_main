# Audio Ads Implementation Guide

## Overview
This guide outlines the implementation of audio ads in the music streaming platform, focusing on desktop platforms (Windows, macOS, and web).

## Ad Service Architecture

### 1. Ad Service Components
- Ad Manager Service
- Ad Scheduler
- Ad Player
- Ad Analytics
- User Preferences

### 2. Implementation Details

#### Ad Manager Service
```dart
class AdManager {
  static const int AD_INTERVAL_MINUTES = 10;
  Timer? _adTimer;
  bool _isAdPlaying = false;
  
  void startAdTimer() {
    _adTimer = Timer(Duration(minutes: AD_INTERVAL_MINUTES), () {
      if (!_isAdPlaying) {
        playAd();
      }
    });
  }
  
  Future<void> playAd() async {
    _isAdPlaying = true;
    // Implement ad playback logic
    _isAdPlaying = false;
    startAdTimer();
  }
}
```

#### Ad Scheduler
- Tracks listening time
- Manages ad intervals
- Handles ad queue
- Respects user preferences

#### Ad Player
- Handles ad playback
- Manages audio transitions
- Implements volume normalization
- Handles ad completion

### 3. User Experience

#### Ad Controls
- Skip button (after 5 seconds)
- Volume control
- Mute option
- Ad preferences

#### Ad Preferences
- Ad frequency settings
- Ad categories
- Do not disturb mode
- Ad-free hours

### 4. Analytics Implementation

#### Tracked Metrics
- Ad impressions
- Ad completion rate
- Skip rate
- User engagement
- Revenue potential

### 5. Implementation Steps

1. **Phase 1: Basic Integration**
   - Implement ad timer
   - Add basic ad playback
   - Create ad controls
   - Set up analytics

2. **Phase 2: Enhanced Features**
   - Add user preferences
   - Implement ad categories
   - Add advanced analytics
   - Optimize ad delivery

3. **Phase 3: Monetization**
   - Integrate with ad networks
   - Implement revenue tracking
   - Add premium ad-free option
   - Optimize ad revenue

### 6. Technical Requirements

#### Dependencies
```yaml
dependencies:
  just_audio: ^0.9.34
  audio_session: ^0.1.16
  shared_preferences: ^2.2.0
  firebase_analytics: ^10.4.0
```

#### Database Tables
```sql
-- Ad impressions tracking
CREATE TABLE ad_impressions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users,
  ad_id TEXT,
  played_at TIMESTAMP,
  completed BOOLEAN,
  skipped BOOLEAN,
  skip_time INTEGER
);

-- User ad preferences
CREATE TABLE user_ad_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users,
  ad_frequency INTEGER,
  do_not_disturb_start TIME,
  do_not_disturb_end TIME,
  categories TEXT[]
);
```

### 7. Testing Strategy

1. **Unit Tests**
   - Ad timer accuracy
   - Ad playback functionality
   - User preference handling
   - Analytics tracking

2. **Integration Tests**
   - Ad insertion in playlist
   - Audio transition handling
   - User control functionality
   - Analytics reporting

3. **User Testing**
   - Ad frequency testing
   - User experience feedback
   - Performance monitoring
   - Revenue optimization

### 8. Future Considerations

1. **Ad Network Integration**
   - Google AdMob
   - Spotify Ad Studio
   - Custom ad network

2. **Premium Features**
   - Ad-free subscription
   - Reduced ad frequency
   - Custom ad preferences

3. **Analytics Enhancement**
   - Advanced metrics
   - Revenue optimization
   - User behavior analysis

## Implementation Timeline

1. **Week 1**: Basic ad service implementation
2. **Week 2**: User controls and preferences
3. **Week 3**: Analytics and testing
4. **Week 4**: Optimization and refinement

## Next Steps

1. Set up ad service infrastructure
2. Implement basic ad playback
3. Add user controls
4. Deploy analytics
5. Begin testing program 
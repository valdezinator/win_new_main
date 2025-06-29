# Listening Time Tracking Feature

## Overview

The listening time tracking feature monitors how long users listen to music and only shows advertisements after they have completed 10 minutes of listening time. This creates a better user experience by allowing users to enjoy music without interruptions initially.

## Features

### Core Functionality

1. **Session Tracking**: Automatically starts and stops listening sessions when music is played or paused
2. **Daily Aggregation**: Tracks total listening time per day across multiple sessions
3. **Ad Eligibility**: Only enables ads after 10 minutes of cumulative listening time
4. **Real-time Updates**: Updates listening time and ad eligibility in real-time
5. **Visual Indicators**: Shows progress towards the 10-minute threshold

### Database Schema

#### Tables

1. **user_listening_sessions**
   - Tracks individual listening sessions
   - Records start/end times and duration
   - Links to user accounts

2. **user_daily_listening**
   - Aggregates daily listening totals
   - Tracks session count per day
   - Optimized for quick queries

#### Functions

- `start_listening_session(p_user_id UUID)`: Starts a new session
- `end_listening_session(p_user_id UUID, p_minutes_listened INTEGER)`: Ends session and updates totals
- `get_user_today_listening_minutes(p_user_id UUID)`: Gets today's total
- `has_user_listened_10_minutes_today(p_user_id UUID)`: Checks ad eligibility
- `get_user_listening_stats(p_user_id UUID, p_days INTEGER)`: Gets listening statistics

## Implementation

### Services

#### ListeningTimeService
- Manages listening sessions
- Tracks real-time listening time
- Provides ad eligibility status
- Handles database interactions

#### AdManagerService (Updated)
- Integrates with listening time tracking
- Only shows ads when user is eligible
- Provides listening time information

### UI Components

#### ListeningTimeIndicator
- Shows current listening progress
- Displays time until ads are enabled
- Indicates active listening sessions
- Visual progress bar

### Integration Points

#### Music Player
- Starts session when music plays
- Ends session when music pauses
- Shows listening time indicator
- Updates in real-time

#### Home Page
- Displays listening progress
- Shows ad eligibility status
- Provides user feedback

## Usage

### For Users

1. **Start Listening**: Simply play music to begin tracking
2. **Monitor Progress**: View listening time in the UI
3. **Ad Experience**: Ads only appear after 10 minutes of listening
4. **Session Management**: Sessions automatically start/stop with playback

### For Developers

#### Starting a Session
```dart
final listeningService = ListeningTimeService();
await listeningService.startSession();
```

#### Ending a Session
```dart
await listeningService.endSession();
```

#### Checking Ad Eligibility
```dart
bool canShowAds = listeningService.canShowAds();
```

#### Getting Progress
```dart
double progress = listeningService.getProgressTowardsAds();
int minutesRemaining = listeningService.getMinutesUntilAds();
```

## Configuration

### Ad Threshold
- Default: 10 minutes
- Configurable in database functions
- Can be adjusted per user or globally

### Update Frequency
- Real-time updates during active sessions
- Periodic database synchronization
- Configurable update intervals

## Security

### Row Level Security (RLS)
- Users can only access their own listening data
- Database functions use SECURITY DEFINER
- Proper authentication checks

### Data Privacy
- Listening data is user-specific
- No cross-user data access
- Secure session management

## Monitoring

### Analytics
- Track listening patterns
- Monitor ad engagement
- Analyze user behavior

### Performance
- Optimized database queries
- Efficient session management
- Minimal UI updates

## Future Enhancements

### Planned Features
1. **Premium Users**: Ad-free experience for premium subscribers
2. **Custom Thresholds**: User-configurable ad timing
3. **Listening Rewards**: Incentives for longer listening sessions
4. **Social Features**: Share listening statistics
5. **Advanced Analytics**: Detailed listening insights

### Technical Improvements
1. **Offline Support**: Track listening when offline
2. **Background Processing**: Continue tracking in background
3. **Cross-Device Sync**: Sync listening time across devices
4. **Machine Learning**: Predict user preferences

## Troubleshooting

### Common Issues

1. **Session Not Starting**
   - Check user authentication
   - Verify database connection
   - Ensure proper initialization

2. **Time Not Updating**
   - Check periodic update timer
   - Verify database functions
   - Monitor error logs

3. **Ads Not Showing**
   - Verify 10-minute threshold reached
   - Check ad eligibility status
   - Ensure ad service integration

### Debug Information

Enable debug logging to monitor:
- Session start/end events
- Database interactions
- Ad eligibility changes
- Error conditions

## Testing

### Unit Tests
- Service functionality
- Database functions
- UI components

### Integration Tests
- End-to-end workflows
- Database interactions
- Ad integration

### User Testing
- Real-world usage scenarios
- Performance under load
- User experience validation 
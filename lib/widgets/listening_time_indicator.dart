import 'package:flutter/material.dart';
import '../services/listening_time_service.dart';

class ListeningTimeIndicator extends StatefulWidget {
  final bool showProgress;
  final bool showTimeRemaining;
  
  const ListeningTimeIndicator({
    super.key,
    this.showProgress = true,
    this.showTimeRemaining = true,
  });

  @override
  State<ListeningTimeIndicator> createState() => _ListeningTimeIndicatorState();
}

class _ListeningTimeIndicatorState extends State<ListeningTimeIndicator> {
  final ListeningTimeService _listeningTimeService = ListeningTimeService();
  
  int _todayListeningMinutes = 0;
  bool _hasReached10Minutes = false;
  bool _isSessionActive = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupListeners();
  }

  Future<void> _loadInitialData() async {
    _todayListeningMinutes = _listeningTimeService.todayListeningMinutes;
    _hasReached10Minutes = _listeningTimeService.hasReached10Minutes;
    _isSessionActive = _listeningTimeService.isSessionActive;
    setState(() {});
  }

  void _setupListeners() {
    _listeningTimeService.addListener(() {
      if (mounted) {
        setState(() {
          _todayListeningMinutes = _listeningTimeService.todayListeningMinutes;
          _hasReached10Minutes = _listeningTimeService.hasReached10Minutes;
          _isSessionActive = _listeningTimeService.isSessionActive;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _listeningTimeService.getProgressTowardsAds();
    final minutesUntilAds = _listeningTimeService.getMinutesUntilAds();
    final formattedTime = _listeningTimeService.getFormattedListeningTime();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _hasReached10Minutes 
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _hasReached10Minutes 
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with status
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hasReached10Minutes ? Icons.check_circle : Icons.timer,
                size: 16,
                color: _hasReached10Minutes ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                _hasReached10Minutes 
                    ? 'Ads Enabled'
                    : 'Listening Progress',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _hasReached10Minutes ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          
          // Progress bar
          if (widget.showProgress) ...[
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _hasReached10Minutes ? Colors.green : Colors.orange,
                ),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
          ],
          
          // Time information
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Today: $formattedTime',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              if (widget.showTimeRemaining && !_hasReached10Minutes) ...[
                const SizedBox(width: 8),
                Text(
                  '• ${minutesUntilAds}m to ads',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                  ),
                ),
              ],
            ],
          ),
          
          // Session indicator
          if (_isSessionActive) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Listening now',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _listeningTimeService.removeListener(() {});
    super.dispose();
  }
} 
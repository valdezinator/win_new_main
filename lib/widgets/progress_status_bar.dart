import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/noise_detection_service.dart';
import '../services/route_tracking_service.dart';

class ProgressStatusBar extends StatefulWidget {
  const ProgressStatusBar({Key? key}) : super(key: key);

  @override
  State<ProgressStatusBar> createState() => _ProgressStatusBarState();
}

class _ProgressStatusBarState extends State<ProgressStatusBar> {
  final NoiseDetectionService _noiseDetectionService = NoiseDetectionService();
  final RouteTrackingService _routeTrackingService = RouteTrackingService();
  final AudioService _audioService = AudioService();
  
  bool _noiseAdaptiveActive = false;
  bool _routeCacheActive = false;
  
  @override
  void initState() {
    super.initState();
    _setupListeners();
  }
    void _setupListeners() {
    _noiseDetectionService.addListener(_updateState);
    _routeTrackingService.addListener(_updateState);
    
    // Initialize
    _updateState();
  }
  
  void _updateState() {
    setState(() {
      _noiseAdaptiveActive = _noiseDetectionService.isActive;
      _routeCacheActive = _routeTrackingService.isActive;
    });
  }
  
  @override
  void dispose() {
    _noiseDetectionService.removeListener(_updateState);
    _routeTrackingService.removeListener(_updateState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_noiseAdaptiveActive && !_routeCacheActive) {
      return const SizedBox.shrink(); // Nothing to show
    }
    
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_noiseAdaptiveActive) 
            _buildIndicator(
              'Noise Adaptive', 
              Icons.mic, 
              Colors.blueAccent
            ),
          if (_noiseAdaptiveActive && _routeCacheActive)
            const SizedBox(width: 16),
          if (_routeCacheActive) 
            _buildIndicator(
              'Route Cache', 
              Icons.route, 
              Colors.greenAccent
            ),
        ],
      ),
    );
  }
  
  Widget _buildIndicator(String label, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ],
    );
  }
}

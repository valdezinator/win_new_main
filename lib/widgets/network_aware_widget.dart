import 'dart:async';
import 'package:flutter/material.dart';
import '../services/network_service.dart';

/// A widget that handles loading and error states based on network conditions
class NetworkAwareWidget extends StatefulWidget {
  final Widget Function(BuildContext context, bool isOnline) builder;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final bool showOfflineBanner;
  final Duration retryDelay;
  final VoidCallback? onRetry;

  const NetworkAwareWidget({
    super.key,
    required this.builder,
    this.loadingWidget,
    this.errorWidget,
    this.showOfflineBanner = true,
    this.retryDelay = const Duration(seconds: 3),
    this.onRetry,
  });

  @override
  State<NetworkAwareWidget> createState() => _NetworkAwareWidgetState();
}

class _NetworkAwareWidgetState extends State<NetworkAwareWidget> {
  late final NetworkService _networkService;
  bool _isLoading = true;
  String? _error;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _networkService = NetworkService();
    _networkService.addListener(_handleNetworkChange);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Wait for network service to initialize
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _handleNetworkChange() {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (!_networkService.isOnline) {
        _error = 'No internet connection';
        _scheduleRetry();
      } else {
        _error = null;
        _retryTimer?.cancel();
      }
    });
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(widget.retryDelay, () {
      if (mounted && !_networkService.isOnline) {
        widget.onRetry?.call();
      }
    });
  }

  @override
  void dispose() {
    _networkService.removeListener(_handleNetworkChange);
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        if (_isLoading)
          widget.loadingWidget ?? const Center(child: CircularProgressIndicator())
        else if (_error != null)
          widget.errorWidget ?? _buildErrorWidget()
        else
          widget.builder(context, _networkService.isOnline),

        // Offline banner
        if (widget.showOfflineBanner && !_networkService.isOnline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.red.withOpacity(0.9),
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'You\'re offline',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onRetry,
                        child: const Text(
                          'Retry',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _error ?? 'An error occurred',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 16),
          if (widget.onRetry != null)
            ElevatedButton(
              onPressed: widget.onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// A widget that shows a loading indicator while data is being fetched
class LoadingWidget extends StatelessWidget {
  final String? message;

  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

/// A widget that shows an error message with a retry button
class ErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
} 
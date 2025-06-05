import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';
import 'dart:io';
import 'dart:async';

/// A widget to display and manage user subscriptions
class SubscriptionManagement extends StatefulWidget {
  final PaymentService paymentService;
  final Color accentColor;

  const SubscriptionManagement({
    Key? key,
    required this.paymentService,
    required this.accentColor,
  }) : super(key: key);

  @override
  State<SubscriptionManagement> createState() => _SubscriptionManagementState();
}

class _SubscriptionManagementState extends State<SubscriptionManagement> {
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription? _subscriptionListener;

  @override
  void initState() {
    super.initState();
    _setupSubscriptionListener();
  }

  @override
  void dispose() {
    _subscriptionListener?.cancel();
    super.dispose();
  }

  /// Set up listener for subscription status changes
  void _setupSubscriptionListener() {
    _subscriptionListener = widget.paymentService.subscriptionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Open premium plans page
  Future<void> _openPremiumPlans() async {
    final Uri url = Uri.parse('file://${Platform.isWindows ? '/' : ''}${Directory.current.path}/assets/premium_plans.html');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Premium Plans page')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  /// Cancel current subscription
  Future<void> _cancelSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel your subscription? '
          'You will continue to have access until the end of your billing period.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    
    try {
      final success = await widget.paymentService.cancelSubscription();
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subscription cancelled successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to cancel subscription')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPlan = widget.paymentService.currentPlan;
    final isPremium = widget.paymentService.currentStatus == SubscriptionStatus.premium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current subscription status
        ListTile(
          leading: Icon(
            isPremium ? Icons.workspace_premium : Icons.music_note,
            color: isPremium ? Colors.amber : widget.accentColor,
            size: 28,
          ),
          title: Text(
            isPremium ? 'Premium Subscription' : 'Free Account',
            style: const TextStyle(color: Colors.white, fontSize: 16)
          ),
          subtitle: Text(
            isPremium 
              ? 'Current plan: ${currentPlan?.name ?? 'Premium'}'
              : 'Limited features available',
            style: const TextStyle(color: Colors.white54, fontSize: 14)
          ),
          trailing: isPremium
            ? TextButton.icon(
                onPressed: _cancelSubscription,
                icon: const Icon(Icons.cancel, size: 16),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade300,
                ),
              )
            : ElevatedButton(
                onPressed: _isLoading ? null : _openPremiumPlans,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Get Premium', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
        ),

        // Error message if any
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade300),
            ),
          ),

        // Loading indicator
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

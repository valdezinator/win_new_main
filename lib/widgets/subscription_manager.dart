import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';
import '../services/payment_processor.dart';

class SubscriptionManager extends StatefulWidget {
  const SubscriptionManager({Key? key}) : super(key: key);

  @override
  _SubscriptionManagerState createState() => _SubscriptionManagerState();
}

class _SubscriptionManagerState extends State<SubscriptionManager> {
  final PaymentService _paymentService = PaymentService();
  bool _isLoading = true;
  bool _isProcessing = false;
  List<PremiumPlan> _availablePlans = [];
  SubscriptionStatus _currentStatus = SubscriptionStatus.free;
  PremiumPlan? _currentPlan;

  @override
  void initState() {
    super.initState();
    _loadData();

    // Listen for subscription changes
    _paymentService.subscriptionStream.listen((status) {
      if (mounted) {
        setState(() {
          _currentStatus = status;
          _currentPlan = _paymentService.currentPlan;
        });
      }
    });
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Initialize payment service if not done yet
      await _paymentService.initialize();

      // Load available plans
      List<PremiumPlan> plans = [];
      try {
        plans = await _paymentService.getAvailablePlans();
      } catch (e) {
        debugPrint('Error getting available plans: $e');
        // If we can't get plans from the database, use demo plans
        plans = [
          PremiumPlan(
            id: 'family',
            name: 'Family',
            description: 'For the whole family',
            price: 19.99,
            currency: 'USD',
            billingInterval: BillingInterval.monthly,
            includedFeatures: [
              PremiumFeature(
                id: 'accounts',
                name: 'Up to 6 Premium accounts',
                description: 'For the whole family',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'explicit_control',
                name: 'Control content marked as explicit',
                description: 'Parental controls for explicit content',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'cancel_anytime',
                name: 'Cancel anytime',
                description: 'Cancel your subscription anytime',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'subscribe_or_one_time',
                name: 'Subscribe or one-time payment',
                description: 'Flexible payment options',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'ad_free',
                name: 'Ad-free music listening',
                description: 'Enjoy music without interruptions',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'offline',
                name: 'Download songs for offline',
                description: 'Download music for offline listening',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'hq_audio',
                name: 'High quality audio',
                description: 'Stream in high-quality up to 320kbps',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'unlimited_skips',
                name: 'Unlimited skips',
                description: 'Skip as many songs as you want',
                tier: FeatureTier.premium,
              ),
            ],
            isActive: true,
          ),
          PremiumPlan(
            id: 'duo',
            name: 'Duo',
            description: 'Perfect for couples',
            price: 14.99,
            currency: 'USD',
            billingInterval: BillingInterval.monthly,
            includedFeatures: [
              PremiumFeature(
                id: 'accounts',
                name: '2 Premium accounts',
                description: 'For two people',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'cancel_anytime',
                name: 'Cancel anytime',
                description: 'Cancel your subscription anytime',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'subscribe_or_one_time',
                name: 'Subscribe or one-time payment',
                description: 'Flexible payment options',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'ad_free',
                name: 'Ad-free music listening',
                description: 'Enjoy music without interruptions',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'offline',
                name: 'Download songs for offline',
                description: 'Download music for offline listening',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'hq_audio',
                name: 'High quality audio',
                description: 'Stream in high-quality up to 320kbps',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'unlimited_skips',
                name: 'Unlimited skips',
                description: 'Skip as many songs as you want',
                tier: FeatureTier.premium,
              ),
            ],
            isActive: true,
          ),
          PremiumPlan(
            id: 'single',
            name: 'Single',
            description: 'Individual subscription plan',
            price: 9.99,
            currency: 'USD',
            billingInterval: BillingInterval.monthly,
            includedFeatures: [
              PremiumFeature(
                id: 'accounts',
                name: '1 Premium account',
                description: 'For one person',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'cancel_anytime',
                name: 'Cancel anytime',
                description: 'Cancel your subscription anytime',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'subscribe_or_one_time',
                name: 'Subscribe or one-time payment',
                description: 'Flexible payment options',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'ad_free',
                name: 'Ad-free music listening',
                description: 'Enjoy music without interruptions',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'offline',
                name: 'Download songs for offline',
                description: 'Download music for offline listening',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'hq_audio',
                name: 'High quality audio',
                description: 'Stream in high-quality up to 320kbps',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'unlimited_skips',
                name: 'Unlimited skips',
                description: 'Skip as many songs as you want',
                tier: FeatureTier.premium,
              ),
            ],
            isActive: true,
          ),
        ];
      }

      // Update state with loaded data
      if (mounted) {
        setState(() {
          _availablePlans = plans;
          _currentStatus = _paymentService.currentStatus;
          _currentPlan = _paymentService.currentPlan;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subscription data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading subscription data: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _subscribeToPlan(PremiumPlan plan) async {
    if (_isProcessing) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      // Create checkout session
      final checkoutUrl = await _paymentService.purchaseSubscription(plan.id);
      
      if (checkoutUrl == null) {
        throw Exception('Failed to create checkout session');
      }
      
      // Open checkout URL in browser
      final success = await _paymentService.launchPayment(checkoutUrl);
      
      if (!success) {
        throw Exception('Could not open payment page');
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _cancelSubscription() async {
    if (_isProcessing) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      // Show confirmation dialog
      final shouldCancel = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text(
            'Cancel Subscription',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to cancel your subscription? '
            'You will continue to have access until the end of your billing period.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
              child: const Text('KEEP SUBSCRIPTION'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('CANCEL SUBSCRIPTION'),
            ),
          ],
        ),
      );

      if (shouldCancel != true) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Cancel the subscription
      final success = await _paymentService.cancelSubscription();
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your subscription has been cancelled'),
            backgroundColor: Color(0xFF1DB954),
          ),
        );
      } else {
        throw Exception('Failed to cancel subscription');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCurrentSubscription(),
        const SizedBox(height: 20),
        if (_currentStatus != SubscriptionStatus.premium)
          ..._buildAvailablePlans(),
      ],
    );
  }

  Widget _buildCurrentSubscription() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Subscription',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (_currentStatus == SubscriptionStatus.premium && _currentPlan != null)
              _buildPremiumSubscriptionInfo()
            else
              _buildFreeSubscriptionInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumSubscriptionInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_currentPlan!.name}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_currentPlan!.formattedPrice} ${_currentPlan!.billingIntervalText}',
          style: const TextStyle(
            color: Color(0xFF1DB954),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Included Features:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ..._currentPlan!.includedFeatures.map((feature) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.check, size: 16, color: Color(0xFF1DB954)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feature.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        )),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _cancelSubscription,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isProcessing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'CANCEL SUBSCRIPTION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildFreeSubscriptionInfo() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Free Plan',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'You are currently on the free plan with limited features.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Free Features:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        _FeatureItem(text: 'Standard quality streaming'),
        _FeatureItem(text: '10 free offline downloads.'),
        _FeatureItem(text: 'With ads'),
        SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _buildAvailablePlans() {
    // Show plans in a single row with 3 columns
    return [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'Available Premium Plans',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _availablePlans.map((plan) =>
          Expanded(child: _buildPlanCard(plan))
        ).toList(),
      ),
    ];
  }

  Widget _buildPlanCard(PremiumPlan plan) {
    // Debug print to check included features
    debugPrint('Plan: \'${plan.name}\' features: \'${plan.includedFeatures.map((f) => f.name).toList()}\'');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF404040),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${plan.formattedPrice} ${plan.billingIntervalText}',
              style: const TextStyle(
                color: Color(0xFF1DB954),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              plan.description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Included Features:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            if (plan.includedFeatures.isEmpty)
              const Text(
                'No features listed.',
                style: TextStyle(color: Colors.redAccent),
              )
            else ...plan.includedFeatures.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: Color(0xFF1DB954)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature.name,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : () => _subscribeToPlan(plan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'SUBSCRIBE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String text;
  
  const _FeatureItem({required this.text});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(
            Icons.check,
            size: 16,
            color: Color(0xFF1DB954),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
            id: 'monthly_premium',
            name: 'Premium Monthly',
            description: 'Unlimited access to all premium features with monthly billing',
            price: 9.99,
            currency: 'USD',
            billingInterval: BillingInterval.monthly,
            includedFeatures: [
              PremiumFeature(
                id: 'offline',
                name: 'Offline Listening',
                description: 'Download music for offline listening',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'hq_audio',
                name: 'High-Quality Audio',
                description: 'Stream in high-quality up to 320kbps',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'no_ads',
                name: 'Ad-Free',
                description: 'Enjoy music without interruptions',
                tier: FeatureTier.premium,
              ),
            ],
            isActive: true,
          ),
          PremiumPlan(
            id: 'yearly_premium',
            name: 'Premium Yearly',
            description: 'Unlimited access to all premium features with yearly billing (2 months free)',
            price: 99.99,
            currency: 'USD',
            billingInterval: BillingInterval.yearly,
            includedFeatures: [
              PremiumFeature(
                id: 'offline',
                name: 'Offline Listening',
                description: 'Download music for offline listening',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'hq_audio',
                name: 'High-Quality Audio',
                description: 'Stream in high-quality up to 320kbps',
                tier: FeatureTier.premium,
              ),
              PremiumFeature(
                id: 'no_ads',
                name: 'Ad-Free',
                description: 'Enjoy music without interruptions',
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
          title: const Text('Cancel Subscription'),
          content: const Text(
            'Are you sure you want to cancel your subscription? '
            'You will continue to have access until the end of your billing period.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('KEEP SUBSCRIPTION'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
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
          ),
        );
      } else {
        throw Exception('Failed to cancel subscription');
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Subscription',
              style: Theme.of(context).textTheme.titleLarge,
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_currentPlan!.formattedPrice} ${_currentPlan!.billingIntervalText}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        const Text('Included Features:'),
        const SizedBox(height: 8),
        ..._currentPlan!.includedFeatures.map((feature) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.check, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(feature.name)),
            ],
          ),
        )),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _cancelSubscription,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
              : const Text('CANCEL SUBSCRIPTION'),
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        SizedBox(height: 8),
        Text('You are currently on the free plan with limited features.'),
        SizedBox(height: 12),
        Text('Free Features:'),
        SizedBox(height: 8),
        _FeatureItem(text: 'Standard quality streaming'),
        _FeatureItem(text: 'Limited skips'),
        _FeatureItem(text: 'With ads'),
        SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _buildAvailablePlans() {
    return [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'Available Premium Plans',
          style:  TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      ..._availablePlans.map((plan) => _buildPlanCard(plan)),
    ];
  }

  Widget _buildPlanCard(PremiumPlan plan) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${plan.formattedPrice} ${plan.billingIntervalText}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(plan.description),
            const SizedBox(height: 12),
            const Text('Included Features:'),
            const SizedBox(height: 8),
            ...plan.includedFeatures.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(feature.name)),
                ],
              ),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : () => _subscribeToPlan(plan),
                child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('SUBSCRIBE'),
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
          const Icon(Icons.check, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

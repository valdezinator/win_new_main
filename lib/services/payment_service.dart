import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_processor.dart';

/// PaymentService: Handles all payment-related functionality including
/// subscription management, purchase verification, and payment processing.
class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  
  PaymentService._internal();
  
  final SupabaseClient _supabase = Supabase.instance.client;
  final _subscriptionController = StreamController<SubscriptionStatus>.broadcast();
  final PaymentGateway _paymentGateway = PaymentGateway();
  
  /// Stream to listen for subscription changes
  Stream<SubscriptionStatus> get subscriptionStream => _subscriptionController.stream;
  
  bool _initialized = false;
  SubscriptionStatus _currentStatus = SubscriptionStatus.free;
  
  /// Current subscription status
  SubscriptionStatus get currentStatus => _currentStatus;
  
  /// Premium plan that user is subscribed to (if any)
  PremiumPlan? _currentPlan;
  PremiumPlan? get currentPlan => _currentPlan;
  
  /// Initialize payment service and check current subscription status
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      await _paymentGateway.initialize();
      await _loadSubscriptionStatus();
      _setupSubscriptionListener();
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing payment service: $e');
    }
  }
    /// Load subscription status from local storage or server
  Future<void> _loadSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _supabase.auth.currentUser?.id;
    
    if (userId == null) {
      _currentStatus = SubscriptionStatus.free;
      return;
    }
    
    try {
      // Try to get subscription status from server
      try {
        final response = await _supabase
            .from('user_subscriptions')
            .select('subscription_type, plan_id, expiry_date, payment_status')
            .eq('user_id', userId)
            .maybeSingle();
        
        if (response != null) {
          final expiryDate = DateTime.parse(response['expiry_date']);
          final isActive = expiryDate.isAfter(DateTime.now()) && 
              response['payment_status'] == 'active';
          
          if (isActive) {
            _currentStatus = SubscriptionStatus.premium;
            _loadPlanDetails(response['plan_id']);
          } else {
            _currentStatus = SubscriptionStatus.free;
          }
        } else {
          _currentStatus = SubscriptionStatus.free;
        }
        
        // Cache the result locally
        prefs.setString('subscription_status', _currentStatus.toString());
      } catch (dbError) {
        // Table doesn't exist yet, set to free
        if (dbError.toString().contains('does not exist')) {
          debugPrint('Subscription tables not set up yet - setting free status');
          _currentStatus = SubscriptionStatus.free;
          prefs.setString('subscription_status', _currentStatus.toString());
        } else {
          // Other error, use cached status if available
          final cachedStatus = prefs.getString('subscription_status');
          _currentStatus = cachedStatus == SubscriptionStatus.premium.toString()
              ? SubscriptionStatus.premium
              : SubscriptionStatus.free;
        }
      }
    } catch (e) {
      debugPrint('Error loading subscription: $e');
      // Fall back to cached status if available
      final cachedStatus = prefs.getString('subscription_status');
      _currentStatus = cachedStatus == SubscriptionStatus.premium.toString()
          ? SubscriptionStatus.premium
          : SubscriptionStatus.free;
    }
    
    // Broadcast the current status
    _subscriptionController.add(_currentStatus);
  }
  
  /// Set up real-time listener for subscription changes
  void _setupSubscriptionListener() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    _supabase
        .from('user_subscriptions')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .listen((data) {
          if (data.isNotEmpty) {
            _handleSubscriptionUpdate(data.first);
          }
        });
  }
  
  /// Handle subscription updates from server
  void _handleSubscriptionUpdate(Map<String, dynamic> data) async {
    try {
      final expiryDate = DateTime.parse(data['expiry_date']);
      final isActive = expiryDate.isAfter(DateTime.now()) && 
          data['payment_status'] == 'active';
      
      final newStatus = isActive ? SubscriptionStatus.premium : SubscriptionStatus.free;
      
      if (newStatus != _currentStatus) {
        _currentStatus = newStatus;
        if (newStatus == SubscriptionStatus.premium) {
          await _loadPlanDetails(data['plan_id']);
        } else {
          _currentPlan = null;
        }
        
        // Update local cache
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('subscription_status', _currentStatus.toString());
        
        // Broadcast the updated status
        _subscriptionController.add(_currentStatus);
      }
    } catch (e) {
      debugPrint('Error handling subscription update: $e');
    }
  }
  
  /// Load plan details from the database
  Future<void> _loadPlanDetails(String planId) async {
    try {
      final planData = await _supabase
          .from('subscription_plans')
          .select()
          .eq('id', planId)
          .single();
      
      _currentPlan = PremiumPlan.fromJson(planData);
    } catch (e) {
      debugPrint('Error loading plan details: $e');
    }
  }
  
  /// Process new subscription purchase
  /// Returns a URL to complete payment or null if error occurs
  Future<Uri?> purchaseSubscription(String planId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    
    try {
      // Get plan details
      final plan = await _supabase
          .from('subscription_plans')
          .select('price, name, duration_months, currency')
          .eq('id', planId)
          .single();
      
      // Determine which payment processor to use
      // For simplicity, we'll use the first available one
      final availableProcessors = _paymentGateway.getEnabledProcessors();
      if (availableProcessors.isEmpty) {
        throw Exception('No payment processors available');
      }
      
      Map<String, dynamic> checkoutInfo;
      final processor = availableProcessors.first;
      
      switch (processor) {
        case PaymentProcessor.stripe:
          checkoutInfo = await _paymentGateway.createStripeCheckoutSession(
            planId: planId,
            amount: plan['price'],
            currency: plan['currency'] ?? 'USD',
            description: '${plan['name']} (${plan['duration_months']} months)',
          );
          break;
        case PaymentProcessor.paypal:
          checkoutInfo = await _paymentGateway.createPayPalCheckoutSession(
            planId: planId,
            amount: plan['price'],
            currency: plan['currency'] ?? 'USD',
            description: '${plan['name']} (${plan['duration_months']} months)',
          );
          break;
        default:
          throw Exception('Unsupported payment processor');
      }
      
      // Store the checkout session ID for later verification
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('last_checkout_session', checkoutInfo['session_id']);
      prefs.setString('last_checkout_plan', planId);
      
      // Return the URL to redirect the user to
      return Uri.parse(checkoutInfo['url']);
    } catch (e) {
      debugPrint('Error purchasing subscription: $e');
      return null;
    }
  }
  
  /// Launch a payment URL in the browser
  Future<bool> launchPayment(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching payment URL: $e');
      return false;
    }
  }
  
  /// Cancel the current subscription
  Future<bool> cancelSubscription() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    
    try {
      final response = await _supabase.functions.invoke('cancel-subscription', body: {
        'user_id': userId,
      });
      
      if (response.status != 200) {
        throw Exception('Failed to cancel subscription: ${response.data}');
      }
      
      // The subscription status will be updated via the subscription listener
      return true;
    } catch (e) {
      debugPrint('Error cancelling subscription: $e');
      return false;
    }
  }
  
  /// Verify if a purchase is complete
  Future<bool> verifyPurchase(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPlanId = prefs.getString('last_checkout_plan');
      
      // For demo mode, use simplified flow
      if (_paymentGateway.isDemoMode && lastPlanId != null) {
        final success = await _paymentGateway.processDemoPayment(sessionId, lastPlanId);
        if (success) {
          await _loadSubscriptionStatus();
          return true;
        }
        return false;
      }
      
      // Determine which payment processor was used
      PaymentStatus status;
      
      // Check with Stripe first
      status = await _paymentGateway.verifyStripePayment(sessionId);
      
      // If not found in Stripe, try PayPal
      if (status == PaymentStatus.failed) {
        status = await _paymentGateway.verifyPayPalPayment(sessionId);
      }
      
      // Refresh subscription status
      await _loadSubscriptionStatus();
      
      return status == PaymentStatus.success;
    } catch (e) {
      debugPrint('Error verifying purchase: $e');
      return false;
    }
  }
    /// Get available subscription plans
  Future<List<PremiumPlan>> getAvailablePlans() async {
    try {
      // First try with is_active filter
      try {
        final response = await _supabase
            .from('subscription_plans')
            .select()
            .eq('is_active', true)
            .order('price');
        
        return (response as List)
            .map((plan) => PremiumPlan.fromJson(plan))
            .toList();
      } catch (e) {
        // If the is_active column doesn't exist, get all plans
        final response = await _supabase
            .from('subscription_plans')
            .select()
            .order('price');
        
        return (response as List)
            .map((plan) => PremiumPlan.fromJson(plan))
            .toList();
      }
    } catch (e) {
      debugPrint('Error getting available plans: $e');
      
      // Return demo plans if database tables aren't set up yet
      if (e.toString().contains('does not exist')) {
        return [
          PremiumPlan(
            id: 'monthly_premium',
            name: 'Premium Monthly',
            description: 'Unlimited access to all premium features with monthly billing',
            price: 9.99,
            currency: 'USD',
            billingInterval: BillingInterval.monthly,
            includedFeatures: _getDemoFeatures(),
            isActive: true,
          ),
          PremiumPlan(
            id: 'yearly_premium',
            name: 'Premium Yearly',
            description: 'Unlimited access to all premium features with yearly billing (2 months free)',
            price: 99.99,
            currency: 'USD',
            billingInterval: BillingInterval.yearly,
            includedFeatures: _getDemoFeatures(),
            isActive: true,
          ),
        ];
      }
      
      return [];
    }
  }
  
  /// Get demo features for plans when database isn't available
  List<PremiumFeature> _getDemoFeatures() {
    return [
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
    ];
  }
  
  /// Check if a specific feature is available for the current subscription
  bool isFeatureAvailable(PremiumFeature feature) {
    if (_currentStatus == SubscriptionStatus.free) {
      // Check if feature is in free tier
      return feature.tier == FeatureTier.free;
    }
    
    // For premium users, check if feature is included in their plan
    if (_currentPlan == null) return false;
    return _currentPlan!.includedFeatures.contains(feature);
  }
  
  /// Dispose payment service resources
  void dispose() {
    _subscriptionController.close();
  }
}

/// Represents the status of a user's subscription
enum SubscriptionStatus {
  free,
  premium,
}

/// Represents a premium plan
class PremiumPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final BillingInterval billingInterval;
  final List<PremiumFeature> includedFeatures;
  final bool isActive;
  
  PremiumPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.billingInterval,
    required this.includedFeatures,
    required this.isActive,
  });
  
  /// Create PremiumPlan from JSON
  factory PremiumPlan.fromJson(Map<String, dynamic> json) {
    // Parse features from JSON array
    final List<PremiumFeature> features = [];
    if (json['included_features'] != null) {
      for (final featureData in json['included_features']) {
        features.add(PremiumFeature(
          id: featureData['id'] ?? '',
          name: featureData['name'] ?? '',
          description: featureData['description'] ?? '',
          tier: _parseFeatureTier(featureData['tier']),
        ));
      }
    }
    
    return PremiumPlan(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'USD',
      billingInterval: _parseBillingInterval(json['billing_interval']),
      includedFeatures: features,
      isActive: json['is_active'] ?? true,
    );
  }
  
  /// Format price with currency symbol
  String get formattedPrice {
    final currencySymbol = _getCurrencySymbol(currency);
    return '$currencySymbol$price';
  }
  
  /// Get billing interval text
  String get billingIntervalText {
    switch (billingInterval) {
      case BillingInterval.monthly:
        return 'per month';
      case BillingInterval.yearly:
        return 'per year';
      case BillingInterval.weekly:
        return 'per week';
      case BillingInterval.oneTime:
        return 'one-time payment';
    }
  }
  
  /// Helper function to get currency symbol
  static String _getCurrencySymbol(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      case 'INR':
        return '₹';
      default:
        return currencyCode;
    }
  }
  
  /// Parse billing interval from string
  static BillingInterval _parseBillingInterval(dynamic interval) {
    if (interval == null) return BillingInterval.monthly;
    
    final intervalStr = interval.toString().toLowerCase();
    switch (intervalStr) {
      case 'monthly':
        return BillingInterval.monthly;
      case 'yearly':
        return BillingInterval.yearly;
      case 'weekly':
        return BillingInterval.weekly;
      case 'one_time':
        return BillingInterval.oneTime;
      default:
        return BillingInterval.monthly;
    }
  }
  
  /// Parse feature tier from string
  static FeatureTier _parseFeatureTier(dynamic tier) {
    if (tier == null) return FeatureTier.premium;
    
    final tierStr = tier.toString().toLowerCase();
    switch (tierStr) {
      case 'free':
        return FeatureTier.free;
      case 'basic':
        return FeatureTier.basic;
      case 'standard':
        return FeatureTier.standard;
      case 'premium':
        return FeatureTier.premium;
      default:
        return FeatureTier.premium;
    }
  }
}

/// Available billing intervals for subscriptions
enum BillingInterval {
  monthly,
  yearly,
  weekly,
  oneTime,
}

/// Premium feature tiers
enum FeatureTier {
  free,
  basic,
  standard,
  premium,
}

/// Represents a premium feature
class PremiumFeature {
  final String id;
  final String name;
  final String description;
  final FeatureTier tier;
  
  PremiumFeature({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
  });
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supported payment processors
enum PaymentProcessor {
  stripe,
  paypal,
}

/// Payment status responses
enum PaymentStatus {
  success,
  pending,
  failed,
  cancelled
}

/// PaymentProcessor: Handles integration with payment gateways
class PaymentGateway {
  static final PaymentGateway _instance = PaymentGateway._internal();
  factory PaymentGateway() => _instance;
  
  PaymentGateway._internal();
  
  // Supabase client
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // API keys (loaded from .env or Supabase)
  String? _stripePublicKey;
  String? _paypalClientId;
  
  // Demo mode flag
  bool _demoMode = false;
  
  // Payment processor configuration
  Map<PaymentProcessor, bool> _enabledProcessors = {
    PaymentProcessor.stripe: true, 
    PaymentProcessor.paypal: true
  };
  
  /// Initialize payment processors
  Future<void> initialize() async {
    try {
      await _loadApiKeys();
      await _loadConfiguration();
      debugPrint('Payment processor initialized');
    } catch (e) {
      debugPrint('Error initializing payment processor: $e');
      // Fall back to demo mode if initialization fails
      _demoMode = true;
    }
  }
  
  /// Load API keys from .env file or Supabase
  Future<void> _loadApiKeys() async {
    try {
      // Try loading from Supabase first (more secure)
      final apiKeys = await _supabase.functions.invoke('get-payment-api-keys');
      
      if (apiKeys.status == 200) {
        _stripePublicKey = apiKeys.data['stripe_public_key'];
        _paypalClientId = apiKeys.data['paypal_client_id'];
        return;
      }
    } catch (e) {
      debugPrint('Error loading API keys from Supabase: $e');
    }
    
    // Fall back to .env file (less secure, but easier for development)
    try {
      await dotenv.load();
      _stripePublicKey = dotenv.env['STRIPE_PUBLIC_KEY'];
      _paypalClientId = dotenv.env['PAYPAL_CLIENT_ID'];
    } catch (e) {
      debugPrint('Error loading API keys from .env: $e');
    }
    
    // If still no keys, enable demo mode
    if (_stripePublicKey == null && _paypalClientId == null) {
      debugPrint('No payment API keys found, enabling demo mode');
      _demoMode = true;
    }
  }
    /// Load payment configuration from Supabase
  Future<void> _loadConfiguration() async {
    try {
      try {
        final config = await _supabase
            .from('payment_configuration')
            .select()
            .single();
        
        _enabledProcessors = {
          PaymentProcessor.stripe: config['stripe_enabled'] ?? true,
          PaymentProcessor.paypal: config['paypal_enabled'] ?? true,
        };
        
        _demoMode = config['demo_mode'] ?? false;
      } catch (dbError) {
        // If table doesn't exist, use default configuration
        if (dbError.toString().contains('does not exist')) {
          debugPrint('Payment configuration table not found - using default configuration');
          _enabledProcessors = {
            PaymentProcessor.stripe: true, 
            PaymentProcessor.paypal: true
          };
          _demoMode = true; // Use demo mode by default if table doesn't exist
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error loading payment configuration: $e');
      // Fallback to defaults if any error occurs
      _enabledProcessors = {
        PaymentProcessor.stripe: true, 
        PaymentProcessor.paypal: true
      };
      _demoMode = true;
    }
  }
  
  /// Get enabled payment processors
  List<PaymentProcessor> getEnabledProcessors() {
    return _enabledProcessors.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }
  
  /// Check if demo mode is enabled
  bool get isDemoMode => _demoMode;
  
  /// Create a payment checkout session with Stripe
  Future<Map<String, dynamic>> createStripeCheckoutSession({
    required String planId,
    required double amount,
    required String currency,
    required String description,
    String? customerId,
  }) async {
    if (_demoMode) {
      return _createDemoCheckoutSession(planId, amount);
    }
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[Stripe Checkout] User not authenticated');
        throw Exception('User not authenticated');
      }
      
      // Use Supabase Edge Function to create checkout session
      final params = {
        'plan_id': planId,
        'amount': amount,
        'currency': currency,
        'description': description,
        'user_id': userId,
        'customer_id': customerId,
      };
      debugPrint('[Stripe Checkout] Invoking Edge Function with params: '
          'PlanId: $planId\nAmount: $amount\nCurrency: $currency\nDescription: $description\nUserId: $userId\nCustomerId: $customerId');
      final response = await _supabase.functions.invoke(
        'create-stripe-checkout',
        body: params,
      );
      debugPrint('[Stripe Checkout] Edge Function response: status=${response.status}, data=${response.data}');
      if (response.status != 200) {
        debugPrint('[Stripe Checkout] Failed to create checkout session. Status: ${response.status}, Data: ${response.data}');
        throw Exception('Failed to create checkout session: ${response.data}');
      }
      return response.data;
    } catch (e, stack) {
      debugPrint('[Stripe Checkout] Error creating Stripe checkout session: $e');
      debugPrint('[Stripe Checkout] Stack trace: $stack');
      rethrow;
    }
  }
  
  /// Create a PayPal checkout session
  Future<Map<String, dynamic>> createPayPalCheckoutSession({
    required String planId,
    required double amount,
    required String currency,
    required String description,
  }) async {
    if (_demoMode) {
      return _createDemoCheckoutSession(planId, amount);
    }
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      // Use Supabase Edge Function to create PayPal checkout
      final response = await _supabase.functions.invoke(
        'create-paypal-checkout',
        body: {
          'plan_id': planId,
          'amount': amount,
          'currency': currency,
          'description': description,
          'user_id': userId,
        },
      );
      
      if (response.status != 200) {
        throw Exception('Failed to create PayPal checkout: ${response.data}');
      }
      
      return response.data;
    } catch (e) {
      debugPrint('Error creating PayPal checkout session: $e');
      rethrow;
    }
  }
  
  /// Create a subscription in demo mode
  Future<Map<String, dynamic>> _createDemoCheckoutSession(String planId, double amount) async {
    // For demo mode, generate a fake checkout URL and session ID
    return {
      'session_id': 'demo_${DateTime.now().millisecondsSinceEpoch}',
      'url': 'https://example.com/demo-checkout?plan=$planId&amount=$amount',
      'demo': true,
    };
  }
  
  /// Process a successful demo payment
  Future<bool> processDemoPayment(String sessionId, String planId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      // Get plan details
      final planDetails = await _supabase
          .from('subscription_plans')
          .select('duration_months, price')
          .eq('id', planId)
          .single();
      
      final durationMonths = planDetails['duration_months'] as int;
      final now = DateTime.now();
      final expiryDate = DateTime(
        now.year, 
        now.month + durationMonths, 
        now.day
      );
      
      // Create or update subscription record
      await _supabase.from('user_subscriptions').upsert({
        'user_id': userId,
        'plan_id': planId,
        'subscription_type': 'premium',
        'payment_processor': 'demo',
        'payment_status': 'active',
        'last_payment_date': now.toIso8601String(),
        'expiry_date': expiryDate.toIso8601String(),
        'payment_id': sessionId,
      });
      
      // Save transaction record
      await _supabase.from('payment_transactions').insert({
        'user_id': userId,
        'plan_id': planId,
        'amount': planDetails['price'],
        'currency': 'USD',
        'payment_processor': 'demo',
        'transaction_id': sessionId,
        'status': 'completed',
        'transaction_date': now.toIso8601String(),
      });
      
      return true;
    } catch (e) {
      debugPrint('Error processing demo payment: $e');
      return false;
    }
  }
  
  /// Verify a payment with Stripe
  Future<PaymentStatus> verifyStripePayment(String sessionId) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-stripe-payment',
        body: {'session_id': sessionId},
      );
      
      if (response.status != 200) {
        throw Exception('Failed to verify payment: ${response.data}');
      }
      
      final status = response.data['status'];
      switch (status) {
        case 'complete':
          return PaymentStatus.success;
        case 'pending':
          return PaymentStatus.pending;
        case 'failed':
          return PaymentStatus.failed;
        default:
          return PaymentStatus.failed;
      }
    } catch (e) {
      debugPrint('Error verifying Stripe payment: $e');
      return PaymentStatus.failed;
    }
  }
  
  /// Verify a payment with PayPal
  Future<PaymentStatus> verifyPayPalPayment(String paymentId) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-paypal-payment',
        body: {'payment_id': paymentId},
      );
      
      if (response.status != 200) {
        throw Exception('Failed to verify payment: ${response.data}');
      }
      
      final status = response.data['status'];
      switch (status) {
        case 'COMPLETED':
          return PaymentStatus.success;
        case 'PENDING':
          return PaymentStatus.pending;
        case 'FAILED':
          return PaymentStatus.failed;
        default:
          return PaymentStatus.failed;
      }
    } catch (e) {
      debugPrint('Error verifying PayPal payment: $e');
      return PaymentStatus.failed;
    }
  }
  
  /// Cancel an active subscription
  Future<bool> cancelSubscription() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      
      // Get current subscription
      final subscription = await _supabase
          .from('user_subscriptions')
          .select('id, payment_processor, external_subscription_id')
          .eq('user_id', userId)
          .eq('payment_status', 'active')
          .maybeSingle();
      
      if (subscription == null) {
        // No active subscription to cancel
        return false;
      }
      
      // For demo mode or if no external subscription ID, just update the local record
      if (_demoMode || subscription['external_subscription_id'] == null) {
        await _supabase.from('user_subscriptions').update({
          'payment_status': 'cancelled',
          'cancelled_at': DateTime.now().toIso8601String(),
        }).eq('id', subscription['id']);
        
        return true;
      }
      
      // Otherwise, cancel with the payment provider
      final response = await _supabase.functions.invoke(
        'cancel-subscription',
        body: {
          'subscription_id': subscription['external_subscription_id'],
          'payment_processor': subscription['payment_processor'],
        },
      );
      
      if (response.status != 200) {
        throw Exception('Failed to cancel subscription: ${response.data}');
      }
      
      // Update local record
      await _supabase.from('user_subscriptions').update({
        'payment_status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
      }).eq('id', subscription['id']);
      
      return true;
    } catch (e) {
      debugPrint('Error cancelling subscription: $e');
      return false;
    }
  }
}

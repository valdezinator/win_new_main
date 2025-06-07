import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class BackblazeService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  final Map<String, String> _signedUrlCache = {};
  final Map<String, DateTime> _urlExpiryCache = {};

  Future<String> getSignedUrl(String fileIdentifier) async {
    // Check if we have a valid cached URL
    if (_signedUrlCache.containsKey(fileIdentifier)) {
      final expiryTime = _urlExpiryCache[fileIdentifier];
      if (expiryTime != null && expiryTime.isAfter(DateTime.now())) {
        return _signedUrlCache[fileIdentifier]!;
      }
    }

    try {
      final response = await _supabaseClient.functions.invoke(
        'get-signed-url',
        body: {'fileIdentifier': fileIdentifier},
      );

      if (response.status != 200) {
        throw Exception('Failed to get signed URL: ${response.data}');
      }

      // Fix: handle both String and Map
      final data = response.data is String ? json.decode(response.data) : response.data;
      final signedUrl = data['signedUrl'] as String;

      // Cache the URL with expiry time (1 hour from now)
      _signedUrlCache[fileIdentifier] = signedUrl;
      _urlExpiryCache[fileIdentifier] = DateTime.now().add(const Duration(hours: 1));

      return signedUrl;
    } catch (e) {
      print('Error getting signed URL: $e');
      rethrow;
    }
  }

  Future<String> getImageUrl(String? imageUrl, String? fileIdentifier) async {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return imageUrl;
    }
    
    if (fileIdentifier != null && fileIdentifier.isNotEmpty) {
      return await getSignedUrl(fileIdentifier);
    }

    throw Exception('No valid image URL or file identifier provided');
  }

  Future<String> getAudioUrl(String? audioUrl, String? fileIdentifier) async {
    if (audioUrl != null && audioUrl.isNotEmpty) {
      return audioUrl;
    }
    
    if (fileIdentifier != null && fileIdentifier.isNotEmpty) {
      return await getSignedUrl(fileIdentifier);
    }

    throw Exception('No valid audio URL or file identifier provided');
  }
} 
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class BackblazeService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  final Map<String, String> _signedUrlCache = {};
  final Map<String, DateTime> _urlExpiryCache = {};

  Future<String> getSignedUrl(String fileIdentifier, {String fileType = 'audio'}) async {
    print('BackblazeService: Getting signed URL for $fileType - $fileIdentifier'); // Debug log

    // Check if we have a valid cached URL
    final cacheKey = '$fileIdentifier:$fileType';
    if (_signedUrlCache.containsKey(cacheKey)) {
      final expiryTime = _urlExpiryCache[cacheKey];
      if (expiryTime != null && expiryTime.isAfter(DateTime.now())) {
        print('BackblazeService: Using cached URL for $fileType - $fileIdentifier'); // Debug log
        return _signedUrlCache[cacheKey]!;
      }
    }

    try {
      print('BackblazeService: Requesting new signed URL for $fileType - $fileIdentifier'); // Debug log
      final response = await _supabaseClient.functions.invoke(
        'get-signed-url',
        body: {
          'fileIdentifier': fileIdentifier,
          'fileType': fileType,
        },
      );

      if (response.status != 200) {
        print('BackblazeService: Failed to get signed URL for $fileType - $fileIdentifier: ${response.data}'); // Debug log
        throw Exception('Failed to get signed URL: ${response.data}');
      }

      // Fix: handle both String and Map
      final data = response.data is String ? json.decode(response.data) : response.data;
      final signedUrl = data['signedUrl'] as String;
      print('BackblazeService: Got signed URL for $fileType - $fileIdentifier: $signedUrl'); // Debug log

      // Cache the URL with expiry time (1 hour from now)
      _signedUrlCache[cacheKey] = signedUrl;
      _urlExpiryCache[cacheKey] = DateTime.now().add(const Duration(hours: 1));

      return signedUrl;
    } catch (e) {
      print('BackblazeService: Error getting signed URL for $fileType - $fileIdentifier: $e'); // Debug log
      rethrow;
    }
  }

  Future<String> getImageUrl(String? imageUrl, String? fileIdentifier) async {
    print('BackblazeService: Getting image URL - imageUrl: $imageUrl, fileIdentifier: $fileIdentifier'); // Debug log

    if (imageUrl != null && imageUrl.isNotEmpty) {
      print('BackblazeService: Using direct image URL: $imageUrl'); // Debug log
      return imageUrl;
    }
    
    if (fileIdentifier != null && fileIdentifier.isNotEmpty) {
      final signedUrl = await getSignedUrl(fileIdentifier, fileType: 'image');
      print('BackblazeService: Resolved image URL: $signedUrl'); // Debug log
      return signedUrl;
    }

    throw Exception('No valid image URL or file identifier provided');
  }

  Future<String> getAudioUrl(String? audioUrl, String? fileIdentifier) async {
    print('BackblazeService: Getting audio URL - audioUrl: $audioUrl, fileIdentifier: $fileIdentifier'); // Debug log

    if (audioUrl != null && audioUrl.isNotEmpty) {
      print('BackblazeService: Using direct audio URL: $audioUrl'); // Debug log
      return audioUrl;
    }
    
    if (fileIdentifier != null && fileIdentifier.isNotEmpty) {
      final signedUrl = await getSignedUrl(fileIdentifier, fileType: 'audio');
      print('BackblazeService: Resolved audio URL: $signedUrl'); // Debug log
      return signedUrl;
    }

    throw Exception('No valid audio URL or file identifier provided');
  }
} 
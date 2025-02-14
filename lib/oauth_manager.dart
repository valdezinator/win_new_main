import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_to_front/window_to_front.dart';

class OAuthManager {
  HttpServer? _redirectServer;

  // Replace these with your Google client settings.
  final String clientId;
  final String? clientSecret;
  final Uri authorizationEndpoint =
      Uri.parse("https://accounts.google.com/o/oauth2/v2/auth");
  final Uri tokenEndpoint = Uri.parse("https://oauth2.googleapis.com/token");

  // The scopes you need (e.g., email, profile, etc.)
  final List<String> scopes = ['openid', 'email', 'profile'];

  OAuthManager({required this.clientId, this.clientSecret});

  /// Initiates the login process and returns an authenticated oauth2.Client.
  Future<oauth2.Client> login() async {
    // If a previous server instance is still running, close it.
    await _redirectServer?.close();

    // Bind to an ephemeral port on localhost.
    _redirectServer = await HttpServer.bind('localhost', 0);
    final redirectUri = Uri.parse("http://localhost:${_redirectServer!.port}/auth");

    // Create an authorization code grant.
    var grant = oauth2.AuthorizationCodeGrant(
      clientId,
      authorizationEndpoint,
      tokenEndpoint,
      secret: clientSecret,
      httpClient: _JsonAcceptingHttpClient(),
    );

    // Generate the authorization URL.
    final authorizationUrl = grant.getAuthorizationUrl(redirectUri, scopes: scopes);

    // Launch the external browser.
    await _redirect(authorizationUrl);

    // Wait for the redirect request.
    final queryParams = await _listenForRedirect();

    // Exchange the authorization code for tokens.
    return await grant.handleAuthorizationResponse(queryParams);
  }

  Future<void> _redirect(Uri url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      throw Exception('Could not launch $url');
    }
  }

  Future<Map<String, String>> _listenForRedirect() async {
    final request = await _redirectServer!.first;
    final params = request.uri.queryParameters;

    // Bring your app’s window to the front after login.
    await WindowToFront.activate();

    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
      ..write("Authentication successful! You can close this window.");
    await request.response.close();

    await _redirectServer!.close();
    _redirectServer = null;
    return params;
  }
}

/// A simple HTTP client that adds Accept: application/json to each request.
class _JsonAcceptingHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Accept'] = 'application/json';
    return _inner.send(request);
  }
}

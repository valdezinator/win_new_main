import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

/// Privacy policy explanation widget for noise detection feature
class NoiseDetectionPrivacyPolicy extends StatelessWidget {
  const NoiseDetectionPrivacyPolicy({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text(
        'Noise Adaptive Crossfade Privacy',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionHeader('How it works'),
            const BodyText(
              'Noise Adaptive Crossfade uses your device\'s microphone to detect ambient '
              'noise levels in your environment. When noise increases, music volume and '
              'crossfade smoothness are automatically adjusted for better listening.'
            ),
            
            const SizedBox(height: 16),
            const SectionHeader('Privacy protection'),
            const BodyText(
              '• No audio is recorded or stored\n'
              '• Only volume levels (decibels) are measured\n'
              '• All processing happens on your device\n'
              '• No data is sent to our servers or third parties\n'
              '• Microphone is only active when the feature is enabled and music is playing'
            ),
            
            const SizedBox(height: 16),
            const SectionHeader('Battery usage'),
            const BodyText(
              'This feature is optimized for minimal battery impact:\n'
              '• Sampling occurs briefly every few seconds\n'
              '• Low-power audio processing\n'
              '• Automatically pauses when music isn\'t playing'
            ),
            
            const SizedBox(height: 16),
            const SectionHeader('Your control'),
            const BodyText(
              '• You can disable this feature at any time\n'
              '• When enabled, a visual indicator appears in the player\n'
              '• Permission can be revoked in your device settings'
            ),
            
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                children: [
                  const TextSpan(
                    text: 'For more information, please see our '
                  ),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        // Launch full privacy policy URL
                        launchUrl(Uri.parse('https://cresca.app/privacy'));
                      }
                  ),
                ]
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Privacy policy explanation widget for offline route cache feature  
class RouteTrackingPrivacyPolicy extends StatelessWidget {
  const RouteTrackingPrivacyPolicy({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text(
        'Offline Route Cache Privacy',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionHeader('How it works'),
            const BodyText(
              'Offline Route Cache remembers your common travel routes and areas where '
              'you typically lose connectivity. It predicts when you\'ll enter these '
              'areas and proactively downloads music for offline listening.'
            ),
            
            const SizedBox(height: 16),
            const SectionHeader('Privacy protection'),
            const BodyText(
              '• Location data is stored only on your device\n'
              '• Your routes are never uploaded to our servers\n'
              '• No tracking for advertising or analytics purposes\n'
              '• Data is automatically deleted after 30 days'
            ),
            
            const SizedBox(height: 16),
            const SectionHeader('Battery and data usage'),
            const BodyText(
              '• Location tracking uses battery-efficient settings\n'
              '• Downloads can be restricted to WiFi only\n'
              '• Smart algorithms avoid unnecessary downloads\n'
              '• Background activity pauses when battery is low'
            ),
            
            const SizedBox(height: 16),
            const SectionHeader('Your control'),
            const BodyText(
              '• You can disable this feature at any time\n'
              '• A visual indicator shows when route tracking is active\n'
              '• You can clear all saved route data in Settings\n'
              '• Location permission can be revoked in device settings'
            ),
            
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                children: [
                  const TextSpan(
                    text: 'For more information, please see our '
                  ),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        // Launch full privacy policy URL
                        launchUrl(Uri.parse('https://cresca.app/privacy'));
                      }
                  ),
                ]
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Section header text style
class SectionHeader extends StatelessWidget {
  final String text;
  
  const SectionHeader(this.text, {Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Body text style
class BodyText extends StatelessWidget {
  final String text;
  
  const BodyText(this.text, {Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Colors.grey[300], fontSize: 14, height: 1.5),
    );
  }
}

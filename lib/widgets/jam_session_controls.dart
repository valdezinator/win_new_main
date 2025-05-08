import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/jam_session_service.dart';

class JamSessionControls extends StatefulWidget {
  final String sessionId;
  final String sessionName;
  final String hostName;
  final bool isHost;
  final Function() onEnd;

  const JamSessionControls({
    Key? key,
    required this.sessionId,
    required this.sessionName,
    required this.hostName,
    required this.isHost,
    required this.onEnd,
  }) : super(key: key);

  @override
  _JamSessionControlsState createState() => _JamSessionControlsState();
}

class _JamSessionControlsState extends State<JamSessionControls> {
  final JamSessionService _jamService = JamSessionService();
  bool _showQR = false;
  bool _copiedToClipboard = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Session Header
        Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // User icon/avatar
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Center(
                      child: Icon(Icons.person, size: 16, color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${widget.sessionName}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // End button (for host only) or Leave button (for participants)
              TextButton(
                onPressed: widget.onEnd,
                child: Text(
                  widget.isHost ? 'End' : 'Leave',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Invite section
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invite friends to your Jam',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Copy and share the link with your friends, or ask them to scan the QR code.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),

              // Show QR code or copy link button
              if (_showQR)
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: QrImageView(
                          data: widget.sessionId,
                          version: QrVersions.auto,
                          size: 150,
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showQR = false;
                          });
                        },
                        child: const Text('Hide QR Code', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.content_copy, size: 16),
                        label: Text(
                          _copiedToClipboard ? 'Copied!' : 'Copy link',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.green,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: widget.sessionId));
                          setState(() {
                            _copiedToClipboard = true;
                          });
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) {
                              setState(() {
                                _copiedToClipboard = false;
                              });
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.qr_code, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _showQR = true;
                        });
                      },
                    ),
                  ],
                ),
              
              const SizedBox(height: 16),
              
              // Allow others to change music toggle
              if (widget.isHost)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Let others change what\'s playing',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    StreamBuilder<Map<String, dynamic>?>(
                      stream: _jamService.sessionStream,
                      initialData: _jamService.currentSession,
                      builder: (context, snapshot) {
                        final canOthersChange = snapshot.data?['allow_others_to_change_music'] ?? false;
                        
                        return Switch(
                          value: canOthersChange,
                          onChanged: (value) async {
                            await _jamService.updateAllowOthersToChangeMusic(value);
                          },
                          activeColor: Colors.green,
                        );
                      }
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

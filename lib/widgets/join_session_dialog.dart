import 'package:flutter/material.dart';
import '../services/jam_session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JoinSessionDialog extends StatefulWidget {
  final Function(String sessionId) onJoin;

  const JoinSessionDialog({super.key, required this.onJoin});

  @override
  _JoinSessionDialogState createState() => _JoinSessionDialogState();
}

class _JoinSessionDialogState extends State<JoinSessionDialog> {
  final _sessionIdController = TextEditingController();
  final _jamSessionService = JamSessionService();
  bool _isValidating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _sessionIdController.dispose();
    super.dispose();
  }  Future<void> _validateAndJoin() async {
    final sessionId = _sessionIdController.text.trim();
    
    if (sessionId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a session ID';
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });

    try {
      // Make sure JamSessionService has user ID set
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'You must be signed in to join a session';
          _isValidating = false;
        });
        return;
      }
      
      // Initialize JamSessionService if needed
      if (!_jamSessionService.isInitialized) {
        await _jamSessionService.initialize(currentUser.id);
      }
      
      final exists = await _jamSessionService.checkSessionExists(sessionId);
      
      if (!exists) {
        setState(() {
          _errorMessage = 'Session not found or has expired';
          _isValidating = false;
        });
        return;
      }

      // Check if the session is still active
      final isActive = await _jamSessionService.checkSessionActive(sessionId);
      if (!isActive) {
        setState(() {
          _errorMessage = 'This jam session has expired';
          _isValidating = false;
        });
        return;
      }

      widget.onJoin(sessionId);
      Navigator.of(context).pop();
    } catch (e) {
      print('Error validating session: $e');
      setState(() {
        _errorMessage = 'Failed to join session. Try again.';
        _isValidating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[850],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Join a Jam',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _sessionIdController,
              decoration: InputDecoration(
                hintText: 'Enter Jam ID',
                errorText: _errorMessage,
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                hintStyle: TextStyle(color: Colors.grey[400]),
              ),
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _validateAndJoin(),
            ),
            
            const SizedBox(height: 20),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _isValidating ? null : _validateAndJoin,
                  child: _isValidating 
                    ? const SizedBox(
                        width: 16, 
                        height: 16, 
                        child: CircularProgressIndicator(strokeWidth: 2)
                      )
                    : const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

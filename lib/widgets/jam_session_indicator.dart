import 'package:flutter/material.dart';
import '../services/jam_session_service.dart';

class JamSessionIndicator extends StatelessWidget {
  final bool isHost;
  final String hostName;

  const JamSessionIndicator({
    Key? key,
    required this.isHost,
    required this.hostName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.green.shade800,
            Colors.green.shade600,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.headphones,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            isHost 
                ? 'Jam session active · You\'re the host' 
                : 'Listening in $hostName\'s Jam',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

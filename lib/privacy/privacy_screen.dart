import 'package:flutter/material.dart';
import '../services/security_service.dart';
import 'dart:convert';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  final _securityService = SecurityService();
  bool _isExporting = false;
  bool _isDeleting = false;

  Future<void> _exportUserData() async {
    setState(() => _isExporting = true);
    try {
      final userData = await _securityService.exportUserData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(userData);
      
      // Show data export dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Your Data Export'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Here is all the data we have stored about you:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(jsonStr),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting data: $e')),
      );
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _deleteUserData() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Data'),
        content: const Text(
          'This will permanently delete all your data including playlists, '
          'preferences, and search history. This action cannot be undone. '
          'Are you sure?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      await _securityService.deleteUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data has been deleted')),
        );
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting data: $e')),
      );
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Data'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Privacy Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Data Export Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Export Your Data',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Download a copy of your personal data including playlists, '
                    'preferences, and search history.',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isExporting ? null : _exportUserData,
                    child: _isExporting
                        ? const CircularProgressIndicator()
                        : const Text('Export Data'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Data Deletion Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delete Your Data',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Permanently delete all your personal data. This action cannot '
                    'be undone.',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isDeleting ? null : _deleteUserData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    child: _isDeleting
                        ? const CircularProgressIndicator()
                        : const Text('Delete All Data'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

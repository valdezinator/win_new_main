import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'secure_storage_service.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  
  DownloadService._internal();

  final _downloadProgressController = StreamController<Map<String, double>>.broadcast();
  final _secureStorage = SecureStorageService();
  
  Stream<Map<String, double>> get downloadProgress => _downloadProgressController.stream;

  DateTime _lastUpdate = DateTime.now();
  static const updateInterval = Duration(milliseconds: 100); // Throttle updates

  Future<void> downloadAlbum(Map<String, dynamic> album, List<Map<String, dynamic>> songs) async {
    try {
      final totalItems = songs.length + 1; // +1 for album cover
      var completedItems = 0;
      
      // Download album cover
      if (album['image_url'] != null) {
        await _downloadFile(
          album['image_url'],
          'album_${album['id']}_cover',
          'Album Cover',
          (progress) {
            _downloadProgressController.add({
              'Album Cover': (completedItems + progress) / totalItems
            });
          }
        );
        completedItems++;
      }

      // Download songs sequentially
      for (var song in songs) {
        if (song['audio_url'] != null) {
          final filename = 'song_${song['id']}';
          await _downloadFile(
            song['audio_url'],
            filename,
            song['title'],
            (progress) {
              _downloadProgressController.add({
                song['title']: (completedItems + progress) / totalItems
              });
            }
          );
          completedItems++;
        }
      }

      // Store metadata
      final metadata = {
        'album_id': album['id'],
        'title': album['title'],
        'artist': album['artist'],
        'songs': songs.map((s) => {
          'id': s['id'],
          'title': s['title'],
          'filename': 'song_${s['id']}',
        }).toList(),
        'downloaded_at': DateTime.now().toIso8601String(),
      };

      await _secureStorage.encryptAndSave(
        utf8.encode(json.encode(metadata)),
        'album_${album['id']}_metadata',
      );
    } catch (e) {
      print('Error downloading album: $e');
      rethrow;
    }
  }

  Future<void> _downloadFile(
    String url, 
    String filename, 
    String label,
    void Function(double progress) onProgress
  ) async {
    try {
      final response = await http.get(Uri.parse(url));
      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;

      final chunks = <int>[];
      
      // Process the download in chunks
      for (var byte in response.bodyBytes) {
        chunks.add(byte);
        downloadedBytes++;
        
        // Throttle progress updates
        final now = DateTime.now();
        if (now.difference(_lastUpdate) > updateInterval) {
          onProgress(downloadedBytes / totalBytes);
          _lastUpdate = now;
        }
      }

      await _secureStorage.encryptAndSave(chunks, filename);
      onProgress(1.0); // Ensure we show 100% completion
    } catch (e) {
      print('Error downloading file $filename: $e');
      rethrow;
    }
  }

  Future<bool> isAlbumDownloaded(String albumId) async {
    try {
      final secureDir = await _secureStoragePath;
      final metadataFileName = _generateFileName('album_${albumId}_metadata');
      final metadataFile = File('$secureDir\\$metadataFileName');
      return await metadataFile.exists();
    } catch (e) {
      print('Error checking if album is downloaded: $e');
      return false;
    }
  }

  Future<List<int>> getDecryptedFile(String filename) async {
    return await _secureStorage.decryptFile(filename);
  }

  Future<String> get _secureStoragePath async {
    final appDir = await getApplicationSupportDirectory();
    final encryptedDir = Directory('${appDir.path}\\secure_storage');
    if (!await encryptedDir.exists()) {
      await encryptedDir.create(recursive: true);
    }
    return encryptedDir.path;
  }

  String _generateFileName(String originalName) {
    final bytes = utf8.encode(originalName);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  void dispose() {
    _downloadProgressController.close();
  }
}

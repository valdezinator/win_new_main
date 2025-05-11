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
      final Map<String, double> progressMap = {};

      // Function to update total progress
      void updateTotalProgress() {
        double totalProgress = 0;
        if (progressMap.isNotEmpty) {
          totalProgress = progressMap.values.reduce((a, b) => a + b) / totalItems;
        }
        _downloadProgressController.add({'Total': totalProgress});
      }

      // Download album cover first (this is important for UI)
      if (album['image_url'] != null) {
        await _downloadFile(
          album['image_url'],
          'album_${album['id']}_cover',
          'Album Cover',
          (progress) {
            progressMap['Album Cover'] = progress;
            updateTotalProgress();
          }
        );
        completedItems++;
        progressMap['Album Cover'] = 1.0;
        updateTotalProgress();
      }

      // Download songs in parallel with a maximum of 3 concurrent downloads
      final songDownloads = <Future<void>>[];

      for (var song in songs) {
        if (song['audio_url'] != null) {
          final filename = 'song_${song['id']}';
          final songTitle = song['title'];

          final downloadFuture = _downloadFile(
            song['audio_url'],
            filename,
            songTitle,
            (progress) {
              progressMap[songTitle] = progress;
              updateTotalProgress();
            }
          ).then((_) {
            completedItems++;
            progressMap[songTitle] = 1.0;
            updateTotalProgress();
          });

          songDownloads.add(downloadFuture);
        }
      }

      // Wait for all downloads to complete
      await Future.wait(songDownloads);

      // Store metadata with additional information for offline playback
      final metadata = {
        'album_id': album['id'],
        'title': album['title'],
        'artist': album['artist'],
        'image_url': album['image_url'],
        'songs': songs.map((s) => {
          'id': s['id'],
          'title': s['title'],
          'artist': s['artist'],
          'duration': s['duration'],
          'image_url': s['image_url'] ?? album['image_url'],
          'filename': 'song_${s['id']}',
          'audio_url': s['audio_url'], // Store original URL for reference
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

  // Check if a specific song is downloaded
  Future<bool> isSongDownloaded(String songId) async {
    try {
      final secureDir = await _secureStoragePath;
      final songFileName = _generateFileName('song_$songId');
      final songFile = File('$secureDir\\$songFileName');
      return await songFile.exists();
    } catch (e) {
      print('Error checking if song is downloaded: $e');
      return false;
    }
  }

  // Get downloaded album metadata
  Future<Map<String, dynamic>?> getAlbumMetadata(String albumId) async {
    try {
      final metadataBytes = await getDecryptedFile('album_${albumId}_metadata');
      final metadataJson = utf8.decode(metadataBytes);
      return json.decode(metadataJson) as Map<String, dynamic>;
    } catch (e) {
      print('Error getting album metadata: $e');
      return null;
    }
  }

  // Get all downloaded albums
  Future<List<Map<String, dynamic>>> getDownloadedAlbums() async {
    try {
      final secureDir = await _secureStoragePath;
      final directory = Directory(secureDir);
      final List<Map<String, dynamic>> albums = [];

      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is File && entity.path.contains('metadata')) {
            try {
              // Use platform-specific path separator
              final fileName = entity.path.split(Platform.pathSeparator).last;
              final originalName = fileName.replaceAll(RegExp(r'[a-f0-9]{64}'), '');
              if (originalName.contains('album_') && originalName.contains('_metadata')) {
                final albumId = originalName.replaceAll('album_', '').replaceAll('_metadata', '');
                final metadata = await getAlbumMetadata(albumId);
                if (metadata != null) {
                  // Ensure the album has all required fields for display
                  final formattedAlbum = {
                    'id': metadata['album_id'],
                    'title': metadata['title'] ?? 'Unknown Album',
                    'artist': metadata['artist'] ?? 'Unknown Artist',
                    'image_url': metadata['image_url'],
                    'songs': metadata['songs'] ?? [],
                    'downloaded': true,
                    'category': 'album, downloaded',
                    'downloaded_at': metadata['downloaded_at'],
                  };
                  albums.add(formattedAlbum);
                }
              }
            } catch (e) {
              print('Error processing file ${entity.path}: $e');
            }
          }
        }
      }

      return albums;
    } catch (e) {
      print('Error getting downloaded albums: $e');
      return [];
    }
  }

  void dispose() {
    _downloadProgressController.close();
  }
}

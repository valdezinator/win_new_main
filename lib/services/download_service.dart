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
      // Print detailed album information for debugging
      print('DownloadService: Downloading album with ID: ${album['id']}');
      print('DownloadService: Album ID type: ${album['id'].runtimeType}');

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
        final albumId = album['id']?.toString() ?? '';
        print('DownloadService: Using album ID: $albumId for cover download');

        await _downloadFile(
          album['image_url'],
          'album_${albumId}_cover',
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
      final albumId = album['id']?.toString() ?? '';
      print('Preparing metadata for album ID: $albumId');

      final metadata = {
        'album_id': albumId,
        'title': album['title'] ?? 'Unknown Album',
        'artist': album['artist'] ?? 'Unknown Artist',
        'image_url': album['image_url'],
        'songs': songs.map((s) => {
          'id': s['id'],
          'title': s['title'] ?? 'Unknown Title',
          'artist': s['artist'] ?? album['artist'] ?? 'Unknown Artist',
          'duration': s['duration'],
          'image_url': s['image_url'] ?? album['image_url'],
          'filename': 'song_${s['id']}',
          'audio_url': s['audio_url'], // Store original URL for reference
        }).toList(),
        'downloaded_at': DateTime.now().toIso8601String(),
        'category': 'album, downloaded', // Add category for consistency
      };

      // Ensure we use the same albumId for the metadata filename
      print('Saving metadata for album ID: $albumId with filename: album_${albumId}_metadata');

      // Save the metadata with multiple ID formats to ensure we can find it later
      // First, save with the original ID format
      await _secureStorage.encryptAndSave(
        utf8.encode(json.encode(metadata)),
        'album_${albumId}_metadata',
      );

      // Also save with numeric ID if possible (for compatibility with the Downloaded Albums section)
      if (int.tryParse(albumId) != null) {
        print('Also saving metadata with numeric ID: ${int.parse(albumId)}');
        await _secureStorage.encryptAndSave(
          utf8.encode(json.encode(metadata)),
          'album_${int.parse(albumId)}_metadata',
        );
      }
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

      // Only log for specific album IDs to avoid excessive logging
      if (int.tryParse(albumId) != null && int.parse(albumId) <= 10) {
        print('Checking if album $albumId is downloaded');
        print('Looking for metadata file: $metadataFileName');
      }

      final exists = await metadataFile.exists();

      // Only log for albums that exist or specific IDs
      if (exists || (int.tryParse(albumId) != null && int.parse(albumId) <= 10)) {
        print('Album $albumId downloaded status: $exists');
      }

      return exists;
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

  // Get all downloaded albums - simplified approach
  Future<List<Map<String, dynamic>>> getDownloadedAlbums() async {
    try {
      final secureDir = await _secureStoragePath;
      final directory = Directory(secureDir);
      final List<Map<String, dynamic>> albums = [];

      print('Scanning for downloaded albums in: $secureDir');

      if (await directory.exists()) {
        // Get a list of all files in the directory
        final allFiles = await directory.list().toList();
        print('Found ${allFiles.length} files in secure storage directory');

        // Get a list of all album IDs we've downloaded
        final albumIds = await _getDownloadedAlbumIds();
        print('Found ${albumIds.length} potential album IDs');

        // For each album ID, try to get its metadata
        for (final albumId in albumIds) {
          try {
            final metadata = await getAlbumMetadata(albumId);
            if (metadata != null) {
              // Ensure the album has all required fields for display
              final formattedAlbum = {
                'id': metadata['album_id'] ?? albumId,
                'title': metadata['title'] ?? 'Unknown Album',
                'artist': metadata['artist'] ?? 'Unknown Artist',
                'image_url': metadata['image_url'],
                'songs': metadata['songs'] ?? [],
                'downloaded': true,
                'category': 'album, downloaded',
                'downloaded_at': metadata['downloaded_at'],
              };

              print('Adding downloaded album to list: ${formattedAlbum['title']} (ID: ${formattedAlbum['id']})');
              albums.add(formattedAlbum);
            }
          } catch (e) {
            print('Error processing album $albumId: $e');
          }
        }
      }

      print('Found ${albums.length} downloaded albums');
      return albums;
    } catch (e) {
      print('Error getting downloaded albums: $e');
      return [];
    }
  }

  // Helper method to get all album IDs that have been downloaded
  Future<List<String>> _getDownloadedAlbumIds() async {
    final List<String> albumIds = [];
    final secureDir = await _secureStoragePath;
    final directory = Directory(secureDir);

    try {
      // First, try to directly scan the directory for metadata files
      if (await directory.exists()) {
        final allFiles = await directory.list().toList();
        print('Scanning ${allFiles.length} files for album metadata');

        for (final entity in allFiles) {
          if (entity is File) {
            final fileName = entity.path.split(Platform.pathSeparator).last;

            // Try to extract album ID from the filename
            // The pattern is: hash of 'album_{id}_metadata'
            final originalNamePattern = RegExp(r'album_(.+)_metadata');

            // Check numeric IDs (1-20)
            for (int i = 1; i <= 20; i++) {
              final testId = i.toString();
              final expectedHash = _generateFileName('album_${testId}_metadata');
              if (fileName == expectedHash) {
                albumIds.add(testId);
                print('Found downloaded album with numeric ID: $testId');
                break;
              }
            }

            // Also check for UUID-style IDs that might be used in the "Just the Hits" section
            // Common UUID patterns like: 123e4567-e89b-12d3-a456-426614174000
            final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

            // Check a few common album IDs from the database
            final commonIds = [
              '1', '2', '3', '4', '5',
              // Add specific album IDs from the "Just the Hits" section
              // These are the actual album IDs used in the app
              '6', '7', '8', '9', '10',
              '11', '12', '13', '14', '15',
              // Add all possible formats of album IDs
              // Numeric IDs
              '16', '17', '18', '19', '20',
              // UUID-style IDs
              '00000000-0000-0000-0000-000000000001',
              '00000000-0000-0000-0000-000000000002',
              '00000000-0000-0000-0000-000000000003',
              // Add any specific album IDs you've downloaded
              // You can get these from the debug logs when downloading an album
            ];

            for (final testId in commonIds) {
              final expectedHash = _generateFileName('album_${testId}_metadata');
              if (fileName == expectedHash) {
                albumIds.add(testId);
                print('Found downloaded album with ID: $testId');
                break;
              }
            }
          }
        }
      }

      // If we didn't find any albums, try the direct approach
      if (albumIds.isEmpty) {
        print('No albums found by scanning, trying direct approach');
        // Try numeric IDs
        for (int i = 1; i <= 20; i++) {
          final albumId = i.toString();
          if (await isAlbumDownloaded(albumId)) {
            albumIds.add(albumId);
            print('Found downloaded album with ID: $albumId');
          }
        }
      }
    } catch (e) {
      print('Error getting album IDs: $e');
    }

    return albumIds;
  }

  void dispose() {
    _downloadProgressController.close();
  }
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  
  late final FlutterSecureStorage _secureStorage;
  late Key _key;
  late IV _iv;
  static const String _keyStorageKey = 'encryption_key';
  static const String _ivStorageKey = 'encryption_iv';
  
  SecureStorageService._internal() {
    _secureStorage = const FlutterSecureStorage();
    _initializeEncryption();
  }

  Future<void> _initializeEncryption() async {
    try {
      // Try to get existing key and IV
      final storedKey = await _secureStorage.read(key: _keyStorageKey);
      final storedIV = await _secureStorage.read(key: _ivStorageKey);

      if (storedKey != null && storedIV != null) {
        // Use existing key and IV
        _key = Key(base64.decode(storedKey));
        _iv = IV(base64.decode(storedIV));
      } else {
        // Generate new key and IV
        _key = Key.fromSecureRandom(32);
        _iv = IV.fromSecureRandom(16);
        
        // Store the new key and IV
        await _secureStorage.write(
          key: _keyStorageKey,
          value: base64.encode(_key.bytes),
        );
        await _secureStorage.write(
          key: _ivStorageKey,
          value: base64.encode(_iv.bytes),
        );
      }
    } catch (e) {
      // If anything goes wrong, generate new key and IV
      _key = Key.fromSecureRandom(32);
      _iv = IV.fromSecureRandom(16);
      
      // Try to store the new key and IV
      try {
        await _secureStorage.write(
          key: _keyStorageKey,
          value: base64.encode(_key.bytes),
        );
        await _secureStorage.write(
          key: _ivStorageKey,
          value: base64.encode(_iv.bytes),
        );
      } catch (e) {
        // If we can't store the key, at least we have a valid one for this session
        print('Warning: Could not persist encryption key: $e');
      }
    }
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

  Future<File> encryptAndSave(List<int> data, String filename) async {
    // Ensure encryption is initialized
    if (_key == null || _iv == null) {
      await _initializeEncryption();
    }

    final encrypter = Encrypter(AES(_key));
    final encrypted = encrypter.encryptBytes(data, iv: _iv);
    
    final secureDir = await _secureStoragePath;
    final secureFileName = _generateFileName(filename);
    final file = File('$secureDir\\$secureFileName');
    
    await file.writeAsBytes(encrypted.bytes);
    return file;
  }

  Future<List<int>> decryptFile(String filename) async {
    // Ensure encryption is initialized
    if (_key == null || _iv == null) {
      await _initializeEncryption();
    }

    final secureDir = await _secureStoragePath;
    final secureFileName = _generateFileName(filename);
    final file = File('$secureDir\\$secureFileName');
    
    if (!await file.exists()) {
      throw const FileSystemException('File not found');
    }

    final encrypter = Encrypter(AES(_key));
    final encrypted = Encrypted(await file.readAsBytes());
    return encrypter.decryptBytes(encrypted, iv: _iv);
  }

  // Add method to clear stored encryption keys (useful for testing or if keys are compromised)
  Future<void> clearEncryptionKeys() async {
    await _secureStorage.delete(key: _keyStorageKey);
    await _secureStorage.delete(key: _ivStorageKey);
    // Generate new keys
    await _initializeEncryption();
  }
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  
  SecureStorageService._internal();

  final _key = Key.fromSecureRandom(32);
  final _iv = IV.fromSecureRandom(16);

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
    final encrypter = Encrypter(AES(_key));
    final encrypted = encrypter.encryptBytes(data, iv: _iv);
    
    final secureDir = await _secureStoragePath;
    final secureFileName = _generateFileName(filename);
    final file = File('$secureDir\\$secureFileName');
    
    await file.writeAsBytes(encrypted.bytes);
    return file;
  }

  Future<List<int>> decryptFile(String filename) async {
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
}

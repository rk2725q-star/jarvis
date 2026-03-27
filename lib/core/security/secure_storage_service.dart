import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Handles encrypted storage of API keys using Android Keystore / iOS Keychain
class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static String _baseUrlKey(String provider) => 'url_${provider.toLowerCase()}';
  static String _apiKeyKey(String provider) => 'api_${provider.toLowerCase()}';

  Future<void> saveApiKey(String provider, String key) async {
    await _storage.write(key: _apiKeyKey(provider), value: key.trim());
  }

  Future<String?> getApiKey(String provider) async {
    return await _storage.read(key: _apiKeyKey(provider));
  }

  Future<void> saveBaseUrl(String provider, String url) async {
    await _storage.write(key: _baseUrlKey(provider), value: url);
  }

  Future<String?> getBaseUrl(String provider) async {
    return await _storage.read(key: _baseUrlKey(provider));
  }

  Future<void> deleteApiKey(String provider) async {
    await _storage.delete(key: _apiKeyKey(provider));
  }

  Future<void> saveLocalUrl(String url) async {
    await _storage.write(key: _baseUrlKey('local_model'), value: url);
  }

  Future<String> getLocalUrl() async {
    return (await _storage.read(key: _baseUrlKey('local_model'))) ?? 'http://127.0.0.1:8080';
  }

  Future<Map<String, String?>> getAllKeys() async {
    final Map<String, String?> keys = {};
    for (final p in ['gemini', 'ollama', 'nvidia', 'deepseek', 'ollamaCloud', 'llamaCpp']) {
      keys[p] = await getApiKey(p);
    }
    return keys;
  }
}

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AuthService {
  final _secureStorage = FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  Future<bool> get isBiometricAvailable async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyWithBiometrics({
    String reason = 'Odblokuj, aby kontynuować',
  }) async {
    try {
      await _localAuth.stopAuthentication();
    } catch (_) {}
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      print('Biometric auth error: $e');
      return false;
    }
  }

  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  String patternToString(List<int> pattern) {
    return pattern.join(',');
  }

  bool verifyPassword(String entered, String? storedHash) {
    if (storedHash == null) return false;
    return hashPassword(entered) == storedHash;
  }

  bool verifyPattern(List<int> pattern, String? storedHash) {
    if (storedHash == null) return false;
    return hashPassword(patternToString(pattern)) == storedHash;
  }

  Future<void> writeHash(String key, String hash) =>
      _secureStorage.write(key: key, value: hash);

  Future<String?> readHash(String key) => _secureStorage.read(key: key);

  Future<void> deleteHash(String key) => _secureStorage.delete(key: key);

  bool canSkipAuth(DateTime? lastAuthTime, String? lastAuthUrl, String urlString) {
    if (lastAuthTime == null) return false;
    if (DateTime.now().difference(lastAuthTime).inSeconds > 30) return false;

    final authUri = Uri.tryParse(lastAuthUrl ?? '');
    final currentUri = Uri.tryParse(urlString);
    if (authUri == null || currentUri == null) return false;

    return _baseDomain(authUri.host) == _baseDomain(currentUri.host);
  }

  String _baseDomain(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  }
}

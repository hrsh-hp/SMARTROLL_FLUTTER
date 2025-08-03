import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIDService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  final String _keyChainKey = 'sr_device_id';

  /// Returns a unique device identifier that persists across app reinstalls
  /// - Android: Uses the Android ID which persists until factory reset
  /// - iOS: Uses a UUID stored in the keychain, which persists through app reinstalls
  Future<String> getUniqueDeviceId() async {
    if (Platform.isAndroid) {
      return _getAndroidId();
    } else if (Platform.isIOS) {
      return _getIosId();
    } else {
      throw UnsupportedError('Platform not supported for unique ID');
    }
  }

  Future<String> _getAndroidId() async {
    final AndroidDeviceInfo androidInfo = await _deviceInfoPlugin.androidInfo;
    // Android ID is a 64-bit number (as a hex string) unique to each combination
    // of app-signing key, user, and device
    return androidInfo.id;
  }

  Future<String> _getIosId() async {
    // Configure keychain item with accessibility and persistence settings
    const iOSOptions = IOSOptions(
      accessibility: KeychainAccessibility.unlocked,
      synchronizable: false, // Don't sync this to iCloud
    );

    // Try to retrieve existing UUID from keychain
    String? deviceId = await _secureStorage.read(
      key: _keyChainKey,
      iOptions: iOSOptions,
    );

    if (deviceId == null) {
      // Generate new UUID if none exists
      deviceId = const Uuid().v4();
      // Store in keychain for persistence
      await _secureStorage.write(
        key: _keyChainKey,
        value: deviceId,
        iOptions: iOSOptions,
      );
    }

    return deviceId;
  }
  /// Deletes the stored device ID from the keychain (iOS only)
  // Optional: Add a method to reset the ID in case it's needed (for testing)
  Future<void> resetDeviceId() async {
    if (Platform.isIOS) {
      await _secureStorage.delete(key: _keyChainKey);
    }
    // For Android, we can't reset the Android ID without factory reset
  }
}

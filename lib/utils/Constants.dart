import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:root_jailbreak_sniffer/rjsniffer.dart';

/// The base URL for the backend API.
const String backendBaseUrl = "https://smartroll.mnv-dev.site";

/// A shared instance of FlutterSecureStorage for the entire application.
final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

// Note: Device ID cannot be a constant here as it's fetched asynchronously at runtime.
// Fetch it where needed (e.g., in the initState of relevant screens) and store it in local state.

String generateShortId({int length = 10}) {
  const chars =
      'abcdefghijklmnopqrstuvwxyz'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      '0123456789'
      '!@#\$%^&*()-_=+[]{}|;:,.<>?';

  final rand = Random.secure();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}

// lib/services/security_service.dart (or a similar name)
class SecurityService {
  // Define the channel name (must match native side)
  static const _platformChannel = MethodChannel(
    'com.smartroll.checks/dev_mode',
  );

  /// Checks if the device is rooted (Android) or jailbroken (iOS).
  Future<bool> isCompromised() async {
    try {
      return await Rjsniffer.amICompromised() ?? false;
    } catch (e) {
      print("Error checking compromised status: $e");
      return false; // Assume not compromised if check fails
    }
  }

  /// Checks if Developer Options are enabled on Android.
  /// Returns false on iOS or if the check fails.
  Future<bool> isDeveloperModeEnabled() async {
    // This check is only relevant for Android
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      // Invoke the native method
      final bool isDevMode = await _platformChannel.invokeMethod(
        'isDeveloperModeEnabled',
      );
      return isDevMode;
    } on PlatformException catch (e) {
      print("Failed to check developer mode: '${e.message}'.");
      return false; // Assume disabled if check fails
    } catch (e) {
      print("Unexpected error checking developer mode: $e");
      return false;
    }
  }

  // Optional: Combine checks
  Future<Map<String, bool>> runAllChecks() async {
    bool compromised = await isCompromised();
    bool devMode = await isDeveloperModeEnabled();
    return {'isCompromised': compromised, 'isDeveloperModeEnabled': devMode};
  }
}

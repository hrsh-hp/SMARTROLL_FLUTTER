import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:root_jailbreak_sniffer/rjsniffer.dart';

/// The base URL for the backend API.
const String backendBaseUrl = "https://smartroll.live";
// const String backendBaseUrl = "https://clear-gently-coral.ngrok-free.app";

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
      debugPrint("Error checking compromised status: $e");
      return false; // Assume not compromised if check fails
    }
  }

  Future<bool> isDebuggerAttached() async {
    try {
      return await Rjsniffer.amIDebugged() ?? false;
    } catch (e) {
      debugPrint("Error checking compromised status: $e");
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
      debugPrint("Failed to check developer mode: '${e.message}'.");
      return false; // Assume disabled if check fails
    } catch (e) {
      debugPrint("Unexpected error checking developer mode: $e");
      return false;
    }
  }

  // Optional: Combine checks
  Future<Map<String, bool>> runAllChecks() async {
    bool compromised = await isCompromised();
    bool devMode = await isDeveloperModeEnabled();
    bool debuggerAttached = await isDebuggerAttached();
    return {
      'isCompromised': compromised,
      'isDeveloperModeEnabled': devMode,
      'isDebuggerAttached': debuggerAttached,
    };
  }
}

class NetwrokUtils {
  static Future<List<ConnectivityResult>> checkConnectivity() async {
    try {
      // Check connectivity status
      final connectivityResultList = await Connectivity().checkConnectivity();
      debugPrint("Connectivity Check Result: $connectivityResultList");
      if (connectivityResultList.contains(ConnectivityResult.none) &&
          connectivityResultList.length > 1) {
        // This state is unusual, treat as disconnected for safety? Or log a warning.
        debugPrint(
          "Warning: Connectivity list contains 'none' along with other types.",
        );
        // Optionally filter out 'none' if other valid connections exist.
        // return connectivityResultList.where((r) => r != ConnectivityResult.none).toList();
      }

      return connectivityResultList;
    } catch (e) {
      // Handle potential errors during the check itself (rare)
      debugPrint("Error checking connectivity: $e");
      // Return 'none' or throw an exception depending on how you want callers to handle this failure
      return [];
    }
  }

  static Future<bool> isConnected() async {
    final results = await checkConnectivity();

    // Check if the list is empty (error during check) or only contains 'none'
    if ((results.isEmpty || results.length == 1) &&
        results.first == ConnectivityResult.none) {
      return false;
    }

    // Check if *any* of the desired connection types are present in the list
    return results.any(
      (result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn, //||
      // result == ConnectivityResult.other,
    );
    // Add ConnectivityResult.other based on future package updates if needed.
  }
}


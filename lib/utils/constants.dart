import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:root_jailbreak_sniffer/rjsniffer.dart';

/// The base URL for the backend API.
// const String backendBaseUrl = "https://smartroll.live";
const String backendBaseUrl = "https://clear-gently-coral.ngrok-free.app";

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

// This is a simple animation controller for the shimmer effect.
// --- Define the Gradient Transform ---
class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;
  final double patternWidth; // Make pattern width configurable

  const _SlideGradientTransform({
    required this.slidePercent,
    required this.patternWidth,
  });

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // Calculate translation based on slidePercent and patternWidth
    // Ensures the pattern starts off-screen left and ends off-screen right
    final double totalTravel = 1.0 + patternWidth;
    final double dx = (slidePercent * totalTravel) - patternWidth;
    return Matrix4.translationValues(dx * bounds.width, 0.0, 0.0);
  }
}
// ---

/// A widget that applies a one-directional shimmer effect to its child.
class ShimmerWidget extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;
  final double gradientPatternWidth;

  const ShimmerWidget({
    required this.child,
    this.baseColor = const Color(0xFF212121),
    this.highlightColor = const Color(0xFFFFFFFF), // Slightly lighter highlight
    this.duration = const Duration(milliseconds: 1000),
    this.gradientPatternWidth = 0.5, // Default width of the moving band
    super.key,
  });

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: widget.duration, // Use duration from widget property
    )..repeat(); // Start one-directional repeat
  }

  @override
  void dispose() {
    _shimmerController.dispose(); // Dispose controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      // Pass the original child down to the builder
      child: widget.child,
      builder: (context, staticChild) {
        // Ensure we have a child to apply the mask to
        if (staticChild == null) {
          return const SizedBox.shrink();
        }
        return ShaderMask(
          blendMode: BlendMode.srcIn, // Apply gradient color to child's shape
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              // Use colors from widget properties
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [
                0.0, // Start base
                0.5, // Peak highlight in pattern center
                1.0, // End base
              ],
              // Apply the sliding transform
              transform: _SlideGradientTransform(
                slidePercent: _shimmerController.value,
                patternWidth:
                    widget.gradientPatternWidth, // Use configurable width
              ),
              // Optional: Clamp tileMode might prevent edge artifacts
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          // Apply the mask to the child passed to the ShimmerWidget
          child: staticChild,
        );
      },
    );
  }
}

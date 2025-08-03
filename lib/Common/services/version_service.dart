import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartroll/Common/utils/constants.dart'; // Assuming backendBaseUrl is here

// Enum to represent the result of the version check
enum VersionStatus {
  upToDate,
  optionalUpdateAvailable, // If latest > current, but current >= minimum
  forceUpdateRequired, // If current < minimum
  error,
}

// Class to hold the check result details
class VersionCheckResult {
  final VersionStatus status;
  final String? latestVersion;
  final String? updateUrl;
  final String? message; // Optional message from backend

  VersionCheckResult({
    required this.status,
    this.latestVersion,
    this.updateUrl,
    this.message,
  });
}

class VersionService {
  // Compares two version strings (e.g., "1.0.8", "1.1.0")
  // Returns:
  // -1 if version1 < version2
  //  0 if version1 == version2
  //  1 if version1 > version2
  // Handles basic semantic versioning (Major.Minor.Patch)
  int _compareVersion(String version1, String version2) {
    List<int> v1Parts = version1.split('.').map(int.parse).toList();
    List<int> v2Parts = version2.split('.').map(int.parse).toList();

    // Pad shorter version with zeros for comparison
    int len = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
    while (v1Parts.length < len) {
      v1Parts.add(0);
    }
    while (v2Parts.length < len) {
      v2Parts.add(0);
    }

    for (int i = 0; i < len; i++) {
      if (v1Parts[i] < v2Parts[i]) return -1;
      if (v1Parts[i] > v2Parts[i]) return 1;
    }
    return 0; // Versions are equal
  }

  Future<VersionCheckResult> checkAppVersion() async {
    try {
      // 1. Get Current App Version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      String platform =
          Platform.isAndroid
              ? 'android'
              : Platform.isIOS
              ? 'ios'
              : 'unknown';
      //debugPrint("Current App Version: $currentVersion, Platform: $platform");

      if (platform == 'unknown') {
        //debugPrint("Unknown platform, skipping version check.");
        return VersionCheckResult(
          status: VersionStatus.upToDate,
        ); // Assume up-to-date on unknown platforms
      }

      // 2. Call Backend API
      final url = Uri.parse(
        '$backendBaseUrl/api/version_check?platform=$platform',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        //debugPrint("Version Check API Response: $data");
        final String latestVersion = data['latestVersion'];
        final String minimumRequiredVersion = data['minimumRequiredVersion'];
        final String updateUrls = data['updateUrl'];
        final String? message = data['updateMessage'];

        //debugPrint("Version Check API Response: Latest=$latestVersion, MinRequired=$minimumRequiredVersion",);

        // 3. Compare Versions
        int comparison = _compareVersion(
          currentVersion,
          minimumRequiredVersion,
        );

        if (comparison < 0) {
          // Current version is less than minimum required version
          return VersionCheckResult(
            status: VersionStatus.forceUpdateRequired,
            latestVersion: latestVersion,
            updateUrl: updateUrls,
            message:
                message ??
                "An important update is required to continue using the app.", // Default message
          );
        } else {
          // Current version is okay, check if optional update is available
          int latestComparison = _compareVersion(currentVersion, latestVersion);
          if (latestComparison < 0) {
            return VersionCheckResult(
              status:
                  VersionStatus
                      .optionalUpdateAvailable, // Or just upToDate if you don't handle optional
              latestVersion: latestVersion,
              updateUrl: updateUrls,
              message: message ?? "An update is available.", // Default message
            );
          } else {
            // Already on the latest version
            return VersionCheckResult(status: VersionStatus.upToDate);
          }
        }
      } else {
        // API call failed (non-200 status)
        //debugPrint("Version check API failed with status: ${response.statusCode}",);
        return VersionCheckResult(status: VersionStatus.error);
      }
    } catch (e) {
      // Network error, parsing error, etc.
      //debugPrint("Error during version check: $e");
      return VersionCheckResult(status: VersionStatus.error);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:smartroll/Screens/login_screen.dart';
import 'dart:convert'; // For jsonDecode/jsonEncode
import 'dart:async'; // For Future, timeout

// Import your screens
import 'attendance_marking_screen.dart';
// import 'login_screen.dart';
import 'error_screen.dart';

// Enum to represent token status clearly
enum TokenStatus {
  valid,
  expiredOrInvalid,
  noToken,
  networkError,
  unknownError,
}

enum RefreshStatus {
  success,
  failed,
  noRefreshToken,
  networkError,
  unknownError,
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  // Ensure base URL is consistent and correct
  static const String _backendBaseUrl = "https://smartroll.mnv-dev.site";

  @override
  void initState() {
    super.initState();
    _performInitialChecks();
  }

  Future<void> _performInitialChecks() async {
    // Optional delay for splash visibility
    await Future.delayed(const Duration(milliseconds: 500));

    Widget nextPage; // Determine the next page dynamically

    try {
      // 1. Check Server Availability
      final serverAvailable = await _checkServerAvailability();
      if (!mounted) return;

      if (!serverAvailable) {
        debugPrint("Server is unavailable. Navigating to Error Screen.");
        nextPage = const ErrorScreen(
          message:
              "Cannot connect to the server. Please check your internet connection and try again later.",
        );
      } else {
        // Server is available, proceed with token checks
        final tokenStatus = await _checkAccessTokenStatus();
        if (!mounted) return;

        switch (tokenStatus) {
          case TokenStatus.valid:
            // Access token is valid, go to main app screen
            nextPage = const AttendanceMarkingScreen();
            break;

          case TokenStatus.expiredOrInvalid:
            // Access token is invalid/expired, try to refresh
            debugPrint("Access token expired/invalid. Attempting refresh...");
            final refreshResult = await _attemptTokenRefresh();
            if (!mounted) return;

            if (refreshResult == RefreshStatus.success) {
              // Refresh succeeded, go to main app screen
              debugPrint("Token refresh successful.");
              nextPage = const AttendanceMarkingScreen();
            } else {
              // Refresh failed (invalid refresh token, network error, etc.)
              // Clear tokens and go to Login Screen
              debugPrint("Token refresh failed. Logging out.");
              await _logout();
              nextPage = const LoginScreen();
            }
            break;

          case TokenStatus.noToken:
            // No access token found, go to Login Screen
            debugPrint("No token found. Navigating to login.");
            nextPage = const LoginScreen();
            break;

          case TokenStatus.networkError:
          case TokenStatus.unknownError:
          default:
            // Network or unknown error during token check, safer to logout and go to Login
            debugPrint("Error during token check ($tokenStatus). Logging out.");
            await _logout();
            nextPage = const LoginScreen();
            // Alternatively, go to Error Screen:
            // nextPage = const ErrorScreen(message: "Failed to verify session. Please restart the app.");
            break;
        }
      }
    } catch (e) {
      // Catch any unexpected errors during the whole process
      debugPrint("Critical error during initial checks: $e");
      await _logout(); // Ensure logout on critical failure
      nextPage = ErrorScreen(
        message: "An unexpected error occurred during startup: ${e.toString()}",
      );
    }

    // Final navigation
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => nextPage),
    );
  }

  // --- Check Server Availability ---
  Future<bool> _checkServerAvailability() async {
    try {
      // Use a simple, non-authenticated endpoint (like base URL or a health check)
      final response = await http
          .get(
            Uri.parse("$_backendBaseUrl/api/check_server_avaibility"),
          ) // Adjust if you have a specific health endpoint
          .timeout(const Duration(seconds: 5));
      // Consider any 2xx or 3xx status as available
      final responseData = jsonDecode(response.body);
      return response.statusCode == 200 && responseData['data'] == true;
    } catch (e) {
      debugPrint("Server check failed: $e");
      return false;
    }
  }

  // --- Check Access Token Status ---
  Future<TokenStatus> _checkAccessTokenStatus() async {
    String? accessToken;
    try {
      accessToken = await _storage.read(key: 'accessToken');
      if (accessToken == null || accessToken.isEmpty) {
        return TokenStatus.noToken;
      }

      // This endpoint should just verify the access token validity
      final verificationUrl = Uri.parse(
        '$_backendBaseUrl/api/check_token_authenticity',
      );
      debugPrint("Verifying token at: $verificationUrl");

      final response = await http
          .get(
            verificationUrl,
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 5));

      debugPrint("Token verification response: ${response.statusCode}");
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          responseData['data']['isAuthenticated'] == true) {
        return TokenStatus.valid;
      } else if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          responseData['data']['isAuthenticated'] == false) {
        return TokenStatus.expiredOrInvalid;
      } else {
        debugPrint(
          "Token verification failed with status: ${response.statusCode}",
        );
        return TokenStatus.unknownError; // Or handle specific server errors
      }
    } on TimeoutException {
      return TokenStatus.networkError;
    } on http.ClientException {
      // Catches network errors (DNS, connection refused etc.)
      return TokenStatus.networkError;
    } catch (e) {
      debugPrint("Error checking token status: $e");
      return TokenStatus.unknownError;
    }
  }

  // --- Attempt Token Refresh ---
  Future<RefreshStatus> _attemptTokenRefresh() async {
    String? refreshToken;
    try {
      refreshToken = await _storage.read(key: 'refreshToken');
      if (refreshToken == null || refreshToken.isEmpty) {
        return RefreshStatus.noRefreshToken;
      }

      // Use the exact refresh URL provided
      final refreshUrl = Uri.parse(
        '$_backendBaseUrl/api/auth/api/token/refresh/',
      );
      debugPrint("Attempting token refresh at: $refreshUrl");

      final response = await http
          .post(
            refreshUrl,
            headers: {'Content-Type': 'application/json'},
            // Send refresh token in the body. Assuming backend expects {'refresh': '...'}
            // based on common practices. If it expects {'param1': '...'}, change the key here.
            body: jsonEncode({'refresh': refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint("Token refresh response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        // *** Use the EXACT keys your backend returns for new tokens ***
        final newAccessToken = responseBody['access'] as String?;
        final newRefreshToken = responseBody['refresh'] as String?;

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          await _storage.write(key: 'accessToken', value: newAccessToken);
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await _storage.write(key: 'refreshToken', value: newRefreshToken);
          }
          return RefreshStatus.success;
        } else {
          // Successful response but missing the new access token - treat as failure
          debugPrint("Refresh response OK, but new access token missing.");
          return RefreshStatus.failed;
        }
      } else {
        // Any non-200 status means refresh failed
        return RefreshStatus.failed;
      }
    } on TimeoutException {
      return RefreshStatus.networkError;
    } on http.ClientException {
      return RefreshStatus.networkError;
    } catch (e) {
      debugPrint("Error attempting token refresh: $e");
      return RefreshStatus.unknownError;
    }
  }

  // --- Logout Helper ---
  Future<void> _logout() async {
    try {
      // Clear both tokens on logout or failure
      await _storage.delete(key: 'accessToken');
      await _storage.delete(key: 'refreshToken');
      debugPrint("Cleared tokens.");
    } catch (e) {
      debugPrint("Error clearing tokens: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Standard splash screen UI
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SMARTROLL',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 30),
            LinearProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text('Initializing...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

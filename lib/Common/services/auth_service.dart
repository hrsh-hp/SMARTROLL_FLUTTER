// lib/services/auth_service.dart

// import 'package:flutter/material.dart'; // Only needed if logout handles navigation directly
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// Assuming constants.dart defines backendBaseUrl and secureStorage
import '../utils/constants.dart';
// Import screens needed for navigation IF handled here (less ideal)
// import 'package:smartroll/Screens/login_screen.dart';

// Enums can live here or in a separate shared file
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

class AuthService {
  // Use the shared instance from constants.dart
  final FlutterSecureStorage _storage = secureStorage;
  // Use the base URL from constants.dart
  static const String _backendBaseUrl = backendBaseUrl;

  /// Checks if the backend server is reachable and responsive.
  Future<bool> checkServerAvailability() async {
    try {
      // Use the specific endpoint from your original splash screen
      final response = await http
          .get(Uri.parse("$_backendBaseUrl/api/check_server_avaibility"))
          .timeout(const Duration(seconds: 10)); // Keep timeout reasonable
      // Check status code and potentially response body as before
      final responseData = jsonDecode(response.body);
      return response.statusCode == 200 && responseData['data'] == true;
    } catch (e) {
      //debugprint("AuthService - Server check failed: $e");
      return false;
    }
  }

  /// Checks the validity of the stored access token against the backend.
  Future<TokenStatus> checkAccessTokenStatus() async {
    String? accessToken;
    try {
      accessToken = await _storage.read(key: 'accessToken');
      if (accessToken == null || accessToken.isEmpty) {
        //debugprint("AuthService - Access token not found.");
        return TokenStatus.noToken;
      }

      // Use the specific endpoint from your original splash screen
      final verificationUrl = Uri.parse(
        '$_backendBaseUrl/api/check_token_authenticity',
      );
      //debugprint("AuthService - Verifying token at: $verificationUrl");

      final response = await http
          .get(
            verificationUrl,
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 5)); // Keep timeout reasonable

      //debugprint( "AuthService - Token verification response: ${response.statusCode}",);
      final responseData = jsonDecode(response.body);

      // Check status code and response body as before
      if (response.statusCode == 200 &&
          responseData['data']?['isAuthenticated'] == true) {
        return TokenStatus.valid;
      } else if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          responseData['data']?['isAuthenticated'] == false) {
        // Consider 401/403 or explicit false from backend as expired/invalid
        return TokenStatus.expiredOrInvalid;
      } else {
        //debugprint( "AuthService - Token verification failed with status: ${response.statusCode}",);
        return TokenStatus.unknownError;
      }
    } on TimeoutException {
      //debugprint("AuthService - Token verification timed out.");
      return TokenStatus.networkError;
    } on http.ClientException {
      // More specific network error catch
      //debugprint("AuthService - Network error during token verification: $e");
      return TokenStatus.networkError;
    } catch (e) {
      //debugprint("AuthService - Error checking token status: $e");
      return TokenStatus.unknownError;
    }
  }

  /// Attempts to refresh the access token using the stored refresh token.
  Future<RefreshStatus> attemptTokenRefresh() async {
    String? refreshToken;
    try {
      refreshToken = await _storage.read(key: 'refreshToken');
      if (refreshToken == null || refreshToken.isEmpty) {
        //debugprint("AuthService - Refresh token not found.");
        return RefreshStatus.noRefreshToken;
      }

      // Use the specific refresh endpoint from your original splash screen
      final refreshUrl = Uri.parse(
        '$_backendBaseUrl/api/auth/api/token/refresh/',
      ); // Double check this path
      //debugprint("AuthService - Attempting token refresh at: $refreshUrl");

      final response = await http
          .post(
            refreshUrl,
            headers: {'Content-Type': 'application/json'},
            // Use the correct key ('refresh' or 'param1' based on backend)
            body: jsonEncode({'refresh': refreshToken}),
          )
          .timeout(
            const Duration(seconds: 10),
          ); // Slightly longer timeout for refresh

      //debugprint("AuthService - Token refresh response: ${response.statusCode}",);

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        // Use the correct keys from your backend response ('access', 'refresh')
        final newAccessToken = responseBody['access'] as String?;
        final newRefreshToken = responseBody['refresh'] as String?;

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          await _storage.write(key: 'accessToken', value: newAccessToken);
          // Only update refresh token if a new one is provided
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await _storage.write(key: 'refreshToken', value: newRefreshToken);
            //debugprint("AuthService - Both tokens refreshed and stored.");
          } else {
            //debugprint("AuthService - Access token refreshed and stored.");
          }
          return RefreshStatus.success;
        } else {
          //debugprint( "AuthService - Refresh response OK, but new access token missing.",);
          return RefreshStatus.failed; // Treat as failure
        }
      } else {
        // Any non-200 status means refresh failed
        //debugprint(  "AuthService - Token refresh failed with status: ${response.statusCode}",);
        return RefreshStatus.failed;
      }
    } on TimeoutException {
      //debugprint("AuthService - Token refresh timed out.");
      return RefreshStatus.networkError;
    } on http.ClientException {
      //debugprint("AuthService - Network error during token refresh: $e");
      return RefreshStatus.networkError;
    } catch (e) {
      //debugprint("AuthService - Error attempting token refresh: $e");
      return RefreshStatus.unknownError;
    }
  }

  /// Clears stored authentication tokens.
  Future<void> clearTokens() async {
    try {
      await _storage.delete(key: 'accessToken');
      await _storage.delete(key: 'refreshToken');
      await _storage.delete(key: 'role');
      //debugprint("AuthService - Cleared tokens.");
    } catch (e) {
      //debugprint("AuthService - Error clearing tokens: $e");
    }
  }

  /// Reads the user's role from secure storage.
  Future<String?> getUserRole() async {
    try {
      return await _storage.read(key: 'role');
    } catch (e) {
      //debugprint("AuthService - Error reading role: $e");
      return null;
    }
  }

  // Optional: If you want the service to handle navigation (less ideal)
  // Future<void> logoutAndNavigate(BuildContext context) async {
  //   await clearTokens();
  //   if (context.mounted) {
  //      Navigator.of(context).pushAndRemoveUntil(
  //        MaterialPageRoute(builder: (_) => const LoginScreen()),
  //        (route) => false,
  //      );
  //   }
  // }
}

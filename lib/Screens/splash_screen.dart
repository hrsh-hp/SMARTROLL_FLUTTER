import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:async'; // For Timer

import 'attendance_marking_screen.dart';
import 'error_screen.dart'; // We will create this screen

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _backendUrl = "https://smartroll.mnv-dev.site";

  @override
  void initState() {
    super.initState();
    _performInitialChecks();
  }

  Future<void> _performInitialChecks() async {
    // Add a small delay for splash screen visibility, optional
    await Future.delayed(const Duration(milliseconds: 500));

    String? errorMessage;
    bool checksPassed = false;

    try {
      // 1. Check Server Availability
      final serverAvailable = await _checkServerAvailability();
      if (!mounted) return;
      if (!serverAvailable) {
        errorMessage = "Server is not available. Please try again later.";
      } else {
        // 2. Check Token Authenticity (only if server is available)
        final tokenAuthentic = await _checkTokenAuthenticity();
        if (!mounted) return;
        if (!tokenAuthentic) {
          errorMessage =
              "Authentication failed or token expired. Please log in again.";
          // In a real app with login, you'd navigate to LoginScreen here
        } else {
          checksPassed = true; // Both checks passed
        }
      }
    } catch (e) {
      debugPrint("Error during initial checks: $e");
      errorMessage = "An unexpected error occurred during startup.";
    }

    // Navigate based on results
    if (!mounted) return; // Final check before navigation

    if (checksPassed) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AttendanceMarkingScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ErrorScreen(
                message: errorMessage ?? "An unknown error occurred.",
              ),
        ),
      );
    }
  }

  // --- Check Functions (Copied from previous example, could be in a utility file) ---
  Future<bool> _checkServerAvailability() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/api/check_server_avaibility'))
          .timeout(const Duration(seconds: 10)); // Add timeout
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Server check failed: $e");
      return false;
    }
  }

  Future<bool> _checkTokenAuthenticity() async {
    try {
      //  final accessToken = await _storage.read(key: 'accessToken');
      final accessToken =
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzQzNzkwMjU1LCJpYXQiOjE3NDM2MTc0NTUsImp0aSI6IjczMWZlY2RiZDdkZDQyMjhiNzI5MDEyMGVmMDQxZGVjIiwidXNlcl9pZCI6MTkyOSwib2JqIjp7InNsdWciOiIyNzU3NzNfMTczMTMwODQ5MSIsInByb2ZpbGUiOnsibmFtZSI6IlNoYWggTWFuYXYgS2F1c2hhbGt1bWFyIiwiZW1haWwiOiIyMmNzbWFuMDMzQGxkY2UuYWMuaW4iLCJyb2xlIjoic3R1ZGVudCJ9LCJzcl9ubyI6MjYsImVucm9sbG1lbnQiOiIyMjAyODMxMDcwMzMiLCJicmFuY2giOnsiYnJhbmNoX25hbWUiOiJURVNUX0JSQU5DSF9GT1JfQ09SRV9URUFNIiwic2x1ZyI6IjU1NmE3OGRhOTRiOTQ3MGVfMTczMjQ3MjY3NTMwNCJ9fX0.p01YPVUyKfqKuYuLtLc3H6N8Pgjk7d51DME0sp_pNgY";
      // "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzQzOTQ1NzI3LCJpYXQiOjE3NDM3NzI5MjcsImp0aSI6ImYyMTc5MjgxMWM5OTQ3NzJiNTBiZjI4NTFhYjU1NWZlIiwidXNlcl9pZCI6Mjg2Miwib2JqIjp7InNsdWciOiJlNGQ1YTlkYzMzZTM0NTQ4XzE3MzIwMDUxOTIyOTkiLCJwcm9maWxlIjp7Im5hbWUiOiJKQU5JIEhBUlNIIE5BUkVTSEJIQUkgIiwiZW1haWwiOiJqYW5paGFyc2g3OTRAZ21haWwuY29tIiwicm9sZSI6InN0dWRlbnQifSwic3Jfbm8iOjIyLCJlbnJvbGxtZW50IjoiMjIwMjgwMTUyMDIyIiwiYnJhbmNoIjp7ImJyYW5jaF9uYW1lIjoiQVJUSUZJQ0lBTCBJTlRFTExJR0VOQ0UgQU5EIE1BQ0hJTkUgTEVBUk5JTkciLCJzbHVnIjoiMzMyNTYxXzE3MzExNDczOTAifX19.jBuNZhGLjjPPpVE99to7MWj1xEBSC9CuboBa83JKBBk";
      if (accessToken.isEmpty) {
        // Check if empty too
        debugPrint("Access token not found for authenticity check.");
        return false; // No token means not authentic
      }
      final response = await http
          .get(
            Uri.parse('$_backendUrl/api/check_token_authenticity'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint("Token authenticity check failed: ${response.statusCode}");
        // Optionally clear the invalid token here?
        // await _storage.delete(key: 'accessToken');
        // await _storage.delete(key: 'refreshToken');
        return false;
      }
      // Consider other non-200 codes as failures too?
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Token check failed: $e");
      return false;
    }
  }
  // --- End Check Functions ---

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // Use scaffold background color from theme
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Optional: Add your app logo here
            // Image.asset('assets/logo.png', height: 100),
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
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text('Initializing...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

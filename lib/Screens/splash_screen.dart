import 'package:flutter/material.dart';
import 'package:smartroll/utils/Constants.dart';
import 'dart:async';

// Import the AuthService and Enums
import '../utils/auth_service.dart';

// Import your screens
import 'attendance_marking_screen.dart';
import 'login_screen.dart';
import 'error_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Instantiate the AuthService
  final AuthService _authService = AuthService();
  final SecurityService _securityService = SecurityService();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Animation setup remains the same
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.repeat(reverse: true);

    // Call the check logic
    _performInitialChecks();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _performInitialChecks() async {
    // Optional delay
    await Future.delayed(const Duration(milliseconds: 500));

    Widget nextPage;
    Map<String, bool> securityStatus = {}; // To hold results

    try {
      try {
        securityStatus = await _securityService.runAllChecks();
        debugPrint(
          "Security Status: Compromised: ${securityStatus['isCompromised']}, DevMode: ${securityStatus['isDeveloperModeEnabled']}",
        );
      } catch (e) {
        debugPrint("Error running security checks: $e");
        // Initialize with defaults if checks fail
        securityStatus = {
          'isCompromised': false,
          'isDeveloperModeEnabled': false,
        };
      }
      if (securityStatus['isecuritysCompromised'] == true) {
        debugPrint(
          "Security check failed (Root/Jailbreak or DevMode ON). Blocking app.",
        );
        String msg =
            securityStatus['isCompromised'] == true
                ? "on rooted/jailbroken devices"
                : "when Developer Options are enabled";
        nextPage = ErrorScreen(
          message:
              "For security reasons, this app cannot run $msg. Please disable these settings.",
          // showRetryButton: false, // No point retrying without changing settings
        );
        // Navigate immediately and stop further checks
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => nextPage),
          );
        }
        return;
      }

      // Use AuthService to check server
      final serverAvailable = await _authService.checkServerAvailability();
      if (!mounted) return;

      if (!serverAvailable) {
        debugPrint("SplashScreen - Server unavailable.");
        nextPage = const ErrorScreen(
          message:
              "Cannot connect to the server. Please check your internet connection and try again later.",
        );
      } else {
        // Use AuthService to check token status
        final tokenStatus = await _authService.checkAccessTokenStatus();
        if (!mounted) return;

        switch (tokenStatus) {
          case TokenStatus.valid:
            debugPrint("SplashScreen - Token valid.");
            nextPage = const AttendanceMarkingScreen();
            break;

          case TokenStatus.expiredOrInvalid:
            debugPrint(
              "SplashScreen - Token expired/invalid, attempting refresh.",
            );
            // Use AuthService to refresh
            final refreshResult = await _authService.attemptTokenRefresh();
            if (!mounted) return;

            if (refreshResult == RefreshStatus.success) {
              debugPrint("SplashScreen - Refresh successful.");
              nextPage = const AttendanceMarkingScreen();
            } else {
              debugPrint("SplashScreen - Refresh failed, logging out.");
              // Use AuthService to clear tokens
              await _authService.clearTokens();
              // Navigate to Login
              nextPage = LoginScreen();
            }
            break;

          case TokenStatus.noToken:
            debugPrint("SplashScreen - No token found.");
            nextPage = LoginScreen();
            break;

          case TokenStatus.networkError:
          case TokenStatus.unknownError:
          default:
            debugPrint(
              "SplashScreen - Token check error ($tokenStatus), logging out.",
            );
            // Use AuthService to clear tokens
            await _authService.clearTokens();
            // Navigate to Login
            nextPage = LoginScreen();
            break;
        }
      }
    } catch (e) {
      // Catch unexpected errors during the orchestration
      debugPrint("SplashScreen - Critical error: $e");
      try {
        await _authService
            .clearTokens(); // Attempt to clear tokens on critical error
      } catch (_) {} // Ignore errors during cleanup
      nextPage = ErrorScreen(
        message: "An unexpected error occurred during startup: ${e.toString()}",
      );
    }

    // Final navigation (remains in SplashScreen)
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => nextPage),
    );
  }

  @override
  Widget build(BuildContext context) {
    // UI remains the same
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: const Column(
                children: [
                  Text(
                    'SMARTROLL',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            // Optional: Add back the progress indicator if desired during checks
            // const SizedBox(height: 30),
            // const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

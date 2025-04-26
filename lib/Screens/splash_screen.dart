import 'package:flutter/material.dart';
import 'package:smartroll/Screens/dialogue_utils.dart';
import 'package:smartroll/utils/constants.dart'; // Assuming SecurityService is here or imported
import 'package:smartroll/utils/effects.dart';
import 'package:smartroll/utils/version_service.dart';
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
  final VersionService _versionService = VersionService();

  @override
  void initState() {
    super.initState();
    // Call the check logic
    _performInitialChecks();
  }

  Future<void> _performInitialChecks() async {
    // Optional delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Initialize variables for final navigation decision
    bool checksPassed = false;
    String? errorMessage;
    // Default nextPage if checks pass but require login
    Widget nextPage = LoginScreen();

    try {
      // --- 0. Version Check ---
      final versionResult = await _versionService.checkAppVersion();
      if (!mounted) return;

      if (versionResult.status == VersionStatus.forceUpdateRequired) {
        // Show blocking dialog and STOP further checks/navigation
        await DialogUtils.showForceUpdateDialog(
          context: context,
          message:
              versionResult.message ??
              "Please update the app to continue.", // Use message from API
          updateUrl: versionResult.updateUrl,
        );
        // Since the dialog is blocking and non-dismissible, execution stops here
        // until the user updates (or somehow kills the app).
        return; // Stop processing
      } else if (versionResult.status == VersionStatus.error) {
        //Block the app (safer if version check is critical)
        errorMessage =
            "Could not verify app version. Please check your connection and try again.";
        checksPassed = false;
      }

      // --- 1. Security Checks ---
      Map<String, bool> securityStatus = {};
      try {
        securityStatus = await _securityService.runAllChecks();
        //debugprint("Security Status: Compromised: ${securityStatus['isCompromised']}, DevMode: ${securityStatus['isDeveloperModeEnabled']}, Debugger ${securityStatus['isDebuggerAttached']}",);
      } catch (e) {
        //debugprint("Error running security checks: $e");
        securityStatus = {
          'isCompromised': false,
          'isDeveloperModeEnabled': false,
          'isDebuggerAttached': false,
        }; // Default to non-blocking if check fails
      }

      if (securityStatus['isCompromised'] == true &&
          securityStatus['isDeveloperModeEnabled'] == true &&
          securityStatus['isDebuggerAttached'] == true) {
        //debugprint( "Security check failed (Root/Jailbreak or DevMode ON). Blocking app.",);
        String msg =
            securityStatus['isCompromised'] == true
                ? "on Rooted/Jailbroken Devices"
                : securityStatus['isDeveloperModeEnabled'] == true
                ? "when Developer Options are enabled"
                : "when USB/Wireless Debugging is enabled";
        errorMessage = "For security reasons, This app cannot run $msg.";
        checksPassed = false;
        // Stop further checks if security fails
      } else {
        // --- 2. Connectivity Check ---
        final bool connected = await NetwrokUtils.isConnected();
        if (!mounted) return;
        //debugprint("SplashScreen - Connectivity result: $connected");
        if (!connected) {
          // Check using the boolean result
          errorMessage =
              "No internet connection. Please check your network settings and try again.";
          checksPassed = false;
        } else {
          // --- 3. Server Availability Check ---
          final serverAvailable = await _authService.checkServerAvailability();
          if (!mounted) return;

          if (!serverAvailable) {
            //debugprint("SplashScreen - Server unavailable.");
            errorMessage =
                "Cannot connect to the server. Please try again later.";
            checksPassed = false;
            // Stop further checks if server unavailable
          } else {
            // --- 4. Token Status Check ---
            final tokenStatus = await _authService.checkAccessTokenStatus();
            if (!mounted) return;

            switch (tokenStatus) {
              case TokenStatus.valid:
                //debugprint("SplashScreen - Token valid.");
                nextPage = const AttendanceMarkingScreen();
                checksPassed =
                    true; // All checks passed, navigate to main screen
                break;

              case TokenStatus.expiredOrInvalid:
                //debugprint(   "SplashScreen - Token expired/invalid, attempting refresh.",  );
                final refreshResult = await _authService.attemptTokenRefresh();
                if (!mounted) return;

                if (refreshResult == RefreshStatus.success) {
                  //debugprint("SplashScreen - Refresh successful.");
                  nextPage = const AttendanceMarkingScreen();
                  checksPassed = true; // All checks passed after refresh
                } else {
                  //debugprint("SplashScreen - Refresh failed, logging out.");
                  await _authService.clearTokens();
                  nextPage = LoginScreen(); // Needs login
                  checksPassed = true; // Check didn't fail, just requires login
                }
                break;

              case TokenStatus.noToken:
                //debugprint("SplashScreen - No token found.");
                nextPage = LoginScreen(); // Needs login
                checksPassed =
                    true; // Check itself didn't fail, just requires login
                break;

              case TokenStatus.networkError:
              case TokenStatus.unknownError:
                // default:
                //debugprint( "SplashScreen - Token check error ($tokenStatus), logging out.",);
                await _authService.clearTokens();
                nextPage = LoginScreen(); // Needs login
                checksPassed = true; // Treat as requiring login after error
                break;
            }
          }
        }
      }
    } catch (e) {
      // Catch unexpected errors during the orchestration
      //debugprint("SplashScreen - Critical error: $e");
      errorMessage =
          "An unexpected error occurred during startup: ${e.toString()}";
      checksPassed = false; // Critical error means checks failed
      try {
        await _authService.clearTokens(); // Attempt cleanup
      } catch (_) {} // Ignore errors during cleanup
    }

    // --- Final Navigation Decision ---
    if (!mounted) return;

    if (checksPassed) {
      // Navigate to the determined nextPage (Attendance or Login)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => nextPage),
      );
    } else {
      // Navigate to ErrorScreen with the specific message
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ErrorScreen(
                // Provide a default message if somehow errorMessage is null
                message: errorMessage ?? "An unknown error occurred.",
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI remains the same
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: ShimmerWidget(
          // Assuming ShimmerWidget is correctly defined
          child: Image.asset(
            'assets/LOGO.webp', // Assuming this asset exists
            width: MediaQuery.of(context).size.width * 0.5,
          ),
        ),
      ),
    );
  }
}

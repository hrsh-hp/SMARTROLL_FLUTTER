import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:smartroll/utils/constants.dart';
import 'package:smartroll/utils/device_id_service.dart';
import 'package:smartroll/utils/effects.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  final String? initialMessage;
  const LoginScreen({this.initialMessage, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final deviceIdService = DeviceIDService();
  bool _isRedirecting = false;
  bool _showRetry = false;
  Timer? _abandonmentTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.initialMessage!),
            backgroundColor: Colors.orange,
          ),
        );
      });
    }
    _initiateLogin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _abandonmentTimer?.cancel();
    super.dispose();
  }

  // --- App Lifecycle Listener ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("LoginScreen Lifecycle State: $state"); // For debugging

    // Check if the app resumed (came back from the browser)
    if (state == AppLifecycleState.resumed && _isRedirecting) {
      // User has likely returned from the browser..
      // The success/failure now depends on the actual callback processing.
      _abandonmentTimer?.cancel();
      debugPrint("App resumed, cancelling abandonment timer.");
      // We can optionally set _isRedirecting false here, but it might not be necessary
      // for now, as the timer is cancelled. If the deep link handler fails,
      setState(() {
        _isRedirecting = false;
      }); // Optional
      // If the app resumes and lands back on THIS screen, it means the deep link handler (elsewhere) either hasn't run yet OR failed OR the user came back manually. Treat this return as needing a retry.
      // A short delay helps avoid race conditions if the deep link handler is *just* about to navigate.
      Future.delayed(const Duration(milliseconds: 300), () {
        // Check if we are still on this screen and redirecting state was active
        if (mounted && _isRedirecting) {
          debugPrint(
            "App resumed, but still on LoginScreen. Assuming manual return or failed callback.",
          );
          // Reset the state to show retry.
          _handleRedirectFailure(
            message: 'Login process interrupted. Please try again.',
          );
        }
        // If the deep link handler successfully navigated away before this delay,
        // mounted will be false or _isRedirecting might be different, and failure won't be triggered.
      });
    }
  }

  Future<void> _initiateLogin() async {
    setState(() {
      _isRedirecting = true;
      _showRetry = false;
    });
    _abandonmentTimer?.cancel(); // Cancel any previous timer

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    try {
      final deviceId = await deviceIdService.getUniqueDeviceId();
      if (!mounted) return;

      final encodedDeviceId = base64Encode(utf8.encode(deviceId));
      final redirectUri = "smartrollauth://callback"; // Your custom scheme

      final Uri loginUri = Uri.parse(
        // Ensure backendBaseUrl has no trailing slash for Uri.parse
        "$backendBaseUrl/login?redirect_uri=${Uri.encodeComponent(redirectUri)}&from_app=true&device_id=${Uri.encodeComponent(encodedDeviceId)}",
      );

      final bool launched = await launchUrl(
        loginUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        // Start a LONGER timer now, purely to detect if the user *never* returns
        _abandonmentTimer = Timer(const Duration(seconds: 90), () {
          //// 90 seconds timeout This timer only fires if the app lifecycle listener didn't cancel it AND this screen is still mounted.
          if (mounted && _isRedirecting) {
            debugPrint("Abandonment timer fired.");
            _handleRedirectFailure(
              message: 'Login timed out. Please try again.',
            );
          }
        });
      } else if (mounted) {
        // Handle immediate launch failure
        debugPrint("launchUrl returned false.");
        _handleRedirectFailure(
          message:
              'Could not open the login page. Please ensure you have a web browser installed.',
        );
      }
    } catch (e) {
      debugPrint("Error during login initiation: $e");
      if (mounted) {
        _handleRedirectFailure(
          message: 'An error occurred while trying to log in: ${e.toString()}',
        );
      }
    }
  }

  void _handleRedirectFailure({String? message}) {
    _abandonmentTimer?.cancel(); // Ensure timer is cancelled on failure too
    // Check mounted again as this can be called from timer callback
    if (mounted) {
      setState(() {
        _isRedirecting = false;
        _showRetry = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message ?? 'Could not complete login. Please try again.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShimmerWidget(
              child: Image.asset(
                'assets/LOGO.webp',
                width: MediaQuery.of(context).size.width * 0.5,
              ),
              // const Text(
              //   'SMARTROLL',
              //   textAlign: TextAlign.center,
              //   style: TextStyle(
              //     fontSize: 35, // Slightly larger maybe?
              //     fontWeight: FontWeight.bold,
              //     // The color here doesn't strictly matter as ShaderMask overrides it,
              //     // but setting it helps visualize the text bounds.
              //     color: Colors.white,
              //     letterSpacing: 5,
              //   ),
              // ),
            ),
            if (_showRetry) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: _initiateLogin,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

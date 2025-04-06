import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:smartroll/utils/Constants.dart';
import 'package:smartroll/utils/device_id_service.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  final String? initialMessage;
  const LoginScreen({this.initialMessage, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final deviceIdService = DeviceIDService();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isRedirecting = false;
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _fadeController.repeat(reverse: true);
    _initiateLogin();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initiateLogin() async {
    setState(() {
      _isRedirecting = true;
      _showRetry = false;
    });

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    
    try {
      final deviceId = await deviceIdService.getUniqueDeviceId();
      if (!mounted) return;

      final Uri loginUri = Uri.parse(
        "$backendBaseUrl/login?redirect_uri=${Uri.encodeComponent("smartrollauth://callback")}&from_app=true&device_id=${Uri.encodeComponent(base64Encode(utf8.encode(deviceId)))}",
      );

      final bool launched = await launchUrl(
        loginUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _handleRedirectFailure();
      } else {
        // Start timeout timer for redirect
        Future.delayed(const Duration(seconds: 15), () {
          if (mounted && _isRedirecting) {
            _handleRedirectFailure();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _handleRedirectFailure();
      }
    }
  }

  void _handleRedirectFailure() {
    setState(() {
      _isRedirecting = false;
      _showRetry = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not complete login. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: const Text(
                'SMARTROLL',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (_showRetry) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: _initiateLogin,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
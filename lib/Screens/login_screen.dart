import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher

class LoginScreen extends StatelessWidget {
  // Optional: Receive an initial message (e.g., if redirected from splash due to error)
  final String? initialMessage;

  const LoginScreen({this.initialMessage, super.key});

  // URL of your web portal's login page that handles auth
  static const String _webPortalLoginUrl =
      "https://smartroll.mnv-dev.site/login"; // EXAMPLE URL
  // The custom URL scheme and host configured for your app
  static const String _appCallbackUrl = "smartrollauth://callback";

  /// Constructs the login URL and launches it in an external browser.
  Future<void> _launchLoginUrl(BuildContext context) async {
    // Construct the URL to open in the browser.
    // We pass the app's callback URL as 'redirect_uri' (or similar param your web expects)
    // and a flag 'from_app=true' so the web frontend knows it was called from the app.
    final Uri loginUri = Uri.parse(
      "$_webPortalLoginUrl?redirect_uri=${Uri.encodeComponent(_appCallbackUrl)}&from_app=true",
    );

    debugPrint("Attempting to launch URL: $loginUri");

    try {
      // Attempt to launch the URL in an external browser application.
      final bool launched = await launchUrl(
        loginUri,
        // Ensures it opens in Chrome/Safari etc., not an in-app webview
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        // Handle the case where the URL couldn't be launched (rare)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open the login page in browser. Is a browser installed?',
            ),
          ),
        );
      }
    } catch (e) {
      // Handle any errors during the launch process
      debugPrint("Error launching URL: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening login page: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use scaffold background color from theme
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch, // Make button wider
            children: [
              // Optional: Display your app logo or title
              const Text(
                'SMARTROLL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 50),

              // Display initial message if provided (e.g., from splash screen error)
              if (initialMessage != null) ...[
                Text(
                  initialMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orangeAccent.shade200),
                ),
                const SizedBox(height: 20),
              ],

              // The main login button
              ElevatedButton.icon(
                icon: const Icon(Icons.login, size: 20),
                label: const Text('Login via Web Portal'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  // Use theme colors or define specific ones
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                // Call the launch function when pressed
                onPressed: () => _launchLoginUrl(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

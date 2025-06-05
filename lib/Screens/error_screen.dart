import 'package:flutter/material.dart';
import 'splash_screen.dart'; // To navigate back for retry

class ErrorScreen extends StatelessWidget {
  final String message;
  final bool showRetryButton; // Option to hide retry for unrecoverable errors

  const ErrorScreen({
    super.key,
    required this.message,
    this.showRetryButton = true, // Default to showing the retry button
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      // Background color is inherited from the main theme
      appBar: AppBar(
        title: SizedBox(
          // height: kToolbarHeight - 2,
          width: MediaQuery.of(context).size.width * 0.4, //100
          child: Image.asset('assets/LOGO.webp', fit: BoxFit.contain),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            // Add padding around the content
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.warning_amber_rounded, 
                  color: Theme.of(context).colorScheme.error,
                  size: 70,
                ),
                const SizedBox(height: 20),

                // Error Title
                Text(
                  'Something Went Wrong', 
                  style: textTheme.headlineSmall?.copyWith(
                    color:
                        Theme.of(
                          context,
                        ).colorScheme.primary, 
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Error Message
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600], // Lighter grey for message body
                    height: 1.4, // Improve line spacing for readability
                  ),
                ),
                const SizedBox(height: 28), // More space before button
                // Retry Button (Conditional)
                if (showRetryButton)
                  OutlinedButton.icon(
                    style: ElevatedButton.styleFrom(
                      // backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor:
                          colorScheme.primary, // Text color on primary
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      textStyle: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10), //  rounding
                      ),
                    ),
                    icon: const Icon(Icons.refresh_outlined, size: 20),
                    label: const Text('Try Again'),
                    onPressed: () {
                      // Navigate back to SplashScreen to retry the checks
                      Navigator.pushReplacement(
                        context,
                        // Use a fade transition for a smoother feel
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const SplashScreen(),
                          transitionsBuilder: (
                            context,
                            animation,
                            secondaryAnimation,
                            child,
                          ) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 300),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

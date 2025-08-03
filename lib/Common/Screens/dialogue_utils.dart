import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:smartroll/Common/services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Utility class for showing common dialogs and bottom sheets.
class DialogUtils {
  // --- Permission Settings Bottom Sheet (Stateless & Light Theme) ---
  static Future<void> showPermissionSettingsSheet({
    required BuildContext context,
    required String title,
    required String content,
    required AppSettingsType settingsType,
    Function(String message, {bool isError})? onErrorSnackbar,
  }) async {
    final theme = Theme.of(context); // Get theme
    final colorScheme = theme.colorScheme; // Get color scheme
    final textTheme = theme.textTheme; // Get text theme

    IconData iconData = Icons.settings_outlined;
    Color iconColor = colorScheme.secondary; // Use secondary color for icon
    if (settingsType == AppSettingsType.location) {
      iconData = Icons.location_on_outlined;
      iconColor = colorScheme.primary; // Use primary for location maybe?
    }
    // ... (add other icon logic if needed) ...

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      // Use theme's bottom sheet background color
      backgroundColor:
          theme.bottomSheetTheme.backgroundColor ?? colorScheme.surface,
      shape: const RoundedRectangleBorder(
        // Consistent shape
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext sheetContext) {
        // Container is mainly for padding now
        return Padding(
          padding: const EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 28.0,
            bottom: 20.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(
                iconData,
                color: iconColor,
                size: 48,
              ), // Use themed icon color
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                // Use theme text style, ensure color comes from theme
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface, // Use theme text color
                ),
              ),
              const SizedBox(height: 12),
              Text(
                content,
                textAlign: TextAlign.center,
                // Use theme text style, ensure color comes from theme (muted)
                style: textTheme.bodyMedium?.copyWith(
                  color:
                      colorScheme.onSurface
                          .withValues(), // Muted theme text color
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        // Use theme color for text/icon
                        foregroundColor: colorScheme.onSurface.withValues(),
                        // Use theme color for border
                        side: BorderSide(
                          color: colorScheme.outline.withValues(),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('DENY'), // Consider 'CANCEL' or 'CLOSE'
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      // Or FilledButton for M3 style
                      style: ElevatedButton.styleFrom(
                        // Use theme colors
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        // Text style can often be inherited from theme's buttonTheme
                        // textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      child: const Text('SETTINGS'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        AppSettings.openAppSettings(
                          type: settingsType,
                        ).catchError((error) {
                          onErrorSnackbar?.call(
                            "Could not open settings automatically.",
                            isError: true,
                          );
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8), // Adjust bottom padding if needed
            ],
          ),
        );
      },
    );
  }

  // --- Manual Marking Dialog (Uses internal StatefulWidget & Light Theme) ---
  static Future<void> showManualMarkingDialog({
    required BuildContext context,
    required String subjectName,
    required Function(String reason) onSubmit,
  }) async {
    final theme = Theme.of(context); // Get theme here for Dialog properties

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          // Use theme's dialog background color
          backgroundColor: theme.dialogTheme.backgroundColor ?? theme.cardColor,
          // Use theme's dialog shape or define consistent one
          shape:
              theme.dialogTheme.shape ??
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: _ManualMarkingDialogContent(
            // Content widget remains the same structure
            subjectName: subjectName,
            onSubmit: onSubmit,
            dialogContext: dialogContext,
          ),
        );
      },
    );
  }

  /// Shows a non-dismissible dialog forcing the user to update the app.
  static Future<void> showForceUpdateDialog({
    required BuildContext context,
    required String message,
    required String? updateUrl, // Store URL
  }) async {
    final theme = Theme.of(context);

    // Function to launch store URL
    Future<void> launchStore() async {
      if (updateUrl != null) {
        final uri = Uri.parse(updateUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          //debugPrint("Could not launch update URL: $updateUrl");
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Could not open the app store."),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        //debugPrint("Update URL is null.");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Update link is missing."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // User MUST update
      builder: (BuildContext dialogContext) {
        // --- Use PopScope with onPopInvokedWithResult ---
        return PopScope(
          canPop: false, // Prevent closing with back button/gesture
          // The 'didPop' parameter indicates if the pop attempt actually occurred
          // The 'result' parameter holds data passed if popped programmatically (not relevant here)
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            // This callback runs *after* a pop attempt.
            // Since canPop is false, didPop should always be false when triggered
            // by a system back gesture or barrier dismiss.
            if (didPop) return; // Should not happen if canPop is false

            // If needed, you could add logic here if the dialog *was* somehow popped,
            // but with canPop: false, the primary goal is just to prevent it.
            //debugPrint( "Pop attempt blocked by PopScope in force update dialog.",);

            // Aggressive option: Exit app if back button is pressed repeatedly?
            // Be very careful with this, generally not recommended UX.
            // SystemNavigator.pop();
          },
          child: AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            icon: Icon(
              Icons.system_update_alt_rounded,
              color: theme.colorScheme.primary,
              size: 48,
            ),
            title: Text(
              'Update Required',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            content: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withAlpha(
                  (0.8 * 255).toInt(),
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.only(
              bottom: 20,
              left: 20,
              right: 20,
            ),
            actions: <Widget>[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: launchStore,
                child: const Text('Update Now'),
              ),
            ],
          ),
        );
        // --- End PopScope ---
      },
    );
  }

  static Future<void> showLogoutConfirmationDialog(BuildContext context) async {
    // Show the confirmation dialog and wait for the user's choice.
    final bool? didConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder: (BuildContext dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          backgroundColor: theme.colorScheme.surface, // Dark background
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'Confirm Logout',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to log out and close the app?',
            style: TextStyle(color: Colors.grey[700]),
          ),
          actions: <Widget>[
            // No / Cancel Button
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false); // Return false when cancelled
              },
            ),
            // Yes / Logout Button
            TextButton(
              child: Text(
                'Logout',
                style: TextStyle(color: theme.colorScheme.error),
              ), // Use error color for emphasis
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true); // Return true when confirmed
              },
            ),
          ],
        );
      },
    );

    // If the user confirmed (dialog returned true), perform the logout.
    if (didConfirm == true) {
      try {
        // Assuming AuthService has a clearTokens method that uses secureStorage
        await AuthService().clearTokens();
      } catch (e) {
        //debugPrint("Error clearing secure storage during logout: $e");
        // Decide if you still want to exit or show an error
      }

      // If the context is still valid, navigate the user to the LoginScreen
      // and remove all previous routes from the stack.
      await SystemNavigator.pop();
      // if (context.mounted) {
      //   Navigator.of(context).pushAndRemoveUntil(
      //     MaterialPageRoute(builder: (context) => const LoginScreen()),
      //     (route) => false,
      //   );
      // }
    }
  }
} // End of DialogUtils Class

// --- Private StatefulWidget for Manual Marking Dialog Content (Light Theme) ---
class _ManualMarkingDialogContent extends StatefulWidget {
  final String subjectName;
  final Function(String reason) onSubmit;
  final BuildContext dialogContext;

  const _ManualMarkingDialogContent({
    required this.subjectName,
    required this.onSubmit,
    required this.dialogContext,
  });

  @override
  State<_ManualMarkingDialogContent> createState() =>
      _ManualMarkingDialogContentState();
}

class _ManualMarkingDialogContentState
    extends State<_ManualMarkingDialogContent> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_validateInput);
  }

  @override
  void dispose() {
    _controller.removeListener(_validateInput);
    _controller.dispose();
    super.dispose();
  }

  void _validateInput() {
    final text = _controller.text.trim();
    final currentlyValid = text.length >= 10;
    if (_isValid != currentlyValid) {
      setState(() {
        _isValid = currentlyValid;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_isValid) {
        widget.onSubmit(_controller.text.trim());
        Navigator.pop(widget.dialogContext);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // Get theme
    final colorScheme = theme.colorScheme; // Get color scheme
    final textTheme = theme.textTheme; // Get text theme

    return Padding(
      padding: const EdgeInsets.all(20.0), // Adjusted padding
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual Marking Request',
              // Use theme text style
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface, // Use theme text color
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subjectName,
              // Use theme text style (muted)
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              maxLines: 3,
              // Use theme text color for input
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Enter reason (min. 10 characters)',
                // Use muted theme text color for hint
                hintStyle: TextStyle(color: colorScheme.onSurface.withValues()),
                filled: true,
                // Use a light fill color from theme or subtle grey
                fillColor: colorScheme.surface.withValues(), // Subtle fill
                // Use theme's input border or define a light one
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(),
                  ), // Subtle border
                ),
                enabledBorder: OutlineInputBorder(
                  // Explicitly define enabled state border
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  // Use primary color for focus border
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                // Use theme error color
                errorStyle: TextStyle(color: colorScheme.error),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().length < 10) {
                  return 'Reason must be at least 10 characters';
                }
                return null;
              },
              onChanged: (_) => _validateInput(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(widget.dialogContext),
                  // Use muted theme color for cancel text
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: colorScheme.onSurface.withValues()),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  // Or FilledButton
                  onPressed: _isValid ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    // Use theme colors
                    // backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

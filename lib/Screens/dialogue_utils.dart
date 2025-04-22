import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';

/// Utility class for showing common dialogs and bottom sheets.
class DialogUtils {
  // --- Permission Settings Bottom Sheet (Stateless) ---
  static Future<void> showPermissionSettingsSheet({
    required BuildContext context,
    required String title,
    required String content,
    required AppSettingsType settingsType,
    Function(String message, {bool isError})? onErrorSnackbar,
  }) async {
    // --- Keep the implementation from the previous step ---
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    IconData iconData = Icons.settings_outlined;
    if (settingsType == AppSettingsType.location) {
      iconData = Icons.location_on_outlined;
    }
    // ... (add other icon logic if needed) ...

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20.0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(iconData, color: colorScheme.onPrimary, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                content,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[400],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[400],
                        side: BorderSide(color: Colors.grey[700]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('DENY'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      child: const Text('SETTINGS'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        AppSettings.openAppSettings(
                          type: settingsType,
                        ).catchError((error) {
                          //debugprint("Error opening settings: $error");
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // --- Manual Marking Bottom Sheet (Uses internal StatefulWidget) ---
  static Future<void> showManualMarkingDialog({
    // Changed name back
    required BuildContext context,
    required String subjectName,
    required Function(String reason) onSubmit,
  }) async {
    // Use showDialog instead of showModalBottomSheet
    await showDialog<void>(
      // Use showDialog
      context: context,
      barrierDismissible: false, // Keep non-dismissible during input
      builder: (BuildContext dialogContext) {
        // Return the private StatefulWidget defined below, wrapped in Dialog properties
        return Dialog(
          // Wrap content in Dialog
          backgroundColor: const Color(0xFF1F1F1F), // Dialog background
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ), // Dialog shape
          child: _ManualMarkingDialogContent(
            // Use the content widget
            subjectName: subjectName,
            onSubmit: (reason) {
              // onSubmit callback from content widget still triggers the passed function
              onSubmit(reason);
              // No need to pop here, content widget's submit handles it
            },
            // Pass dialogContext to allow content widget to pop itself
            dialogContext: dialogContext,
          ),
        );
      },
    );
  }
} // End of DialogUtils Class

// --- Private StatefulWidget for Manual Marking Dialog Content ---
// --- Defined within the same dialog_utils.dart file ---
class _ManualMarkingDialogContent extends StatefulWidget {
  final String subjectName;
  final Function(String reason) onSubmit;
  final BuildContext dialogContext; // Context to pop the dialog

  const _ManualMarkingDialogContent({
    required this.subjectName,
    required this.onSubmit,
    required this.dialogContext, // Receive dialog context
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
        // Pop the dialog using the passed context
        Navigator.pop(widget.dialogContext);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build method remains the same as the original ManualMarkingDialog content
    // It renders the content *inside* the Dialog shell provided by showManualMarkingDialog
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        // Add Form here
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual Marking Request', // Updated Title
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color:
                    Theme.of(context).colorScheme.primary, // Use primary color
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subjectName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
              ), // Adjusted style
            ),
            const SizedBox(height: 16),
            TextFormField(
              // Use TextFormField for validation
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter reason (min. 10 characters)',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2C2C2C), // Darker fill
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ), // Use primary color
                ),
                errorStyle: TextStyle(
                  color: Theme.of(context).colorScheme.error.withValues(),
                ), // Error style
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ), // Adjust padding
              ),
              validator: (value) {
                if (value == null || value.trim().length < 10) {
                  return 'Reason must be at least 10 characters';
                }
                return null;
              },
              onChanged:
                  (_) => _validateInput(), // Update internal state for button
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      () => Navigator.pop(
                        widget.dialogContext,
                      ), // Use passed context
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      _isValid
                          ? _submit
                          : null, // Use internal state for enable/disable
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(), // Style for disabled
                    disabledForegroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ), // Consistent shape
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

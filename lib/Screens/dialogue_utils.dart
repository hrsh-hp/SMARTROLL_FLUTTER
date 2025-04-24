import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';

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

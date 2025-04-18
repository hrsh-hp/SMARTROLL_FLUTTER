import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // For MediaType
import 'package:location/location.dart'; // Keep for LocationData type
import 'package:app_settings/app_settings.dart'; // Keep for AppSettingsType
import 'package:path_provider/path_provider.dart';
import 'package:smartroll/Screens/dialogue_utils.dart';
import 'package:smartroll/Screens/login_screen.dart';

// Import necessary services and utilities used by the logic
import 'package:smartroll/utils/attendace_data_collector.dart';
import 'package:smartroll/utils/constants.dart';
import 'package:smartroll/utils/auth_service.dart';
import 'package:smartroll/utils/device_id_service.dart';

class MarkAttendaceService {
  // Services needed by the handler
  final SecurityService securityService;
  final AttendanceDataCollector dataCollector;
  final AuthService authService;
  final DeviceIDService
  deviceIDService; // Assuming this exists and provides getUniqueDeviceId

  MarkAttendaceService({
    required this.securityService,
    required this.dataCollector,
    required this.authService,
    required this.deviceIDService,
  });

  Future<String?> _saveAudioForDebug(Uint8List audioBytes) async {
    if (!kDebugMode) {
      // Only run this function in debug mode
      return null;
    }

    Directory? directory;
    try {
      // Try getting the public Downloads directory first
      // Note: Access might be restricted on newer Android versions without specific permissions
      // or might return an app-specific directory within Downloads.
      if (Platform.isAndroid) {
        directory =
            await getExternalStorageDirectory(); // Gets primary external storage
        // Try to navigate to a common Downloads path if possible (might fail)
        String downloadsPath = '${directory?.path}/Download';
        directory = Directory(downloadsPath);
        // Check if it exists, if not, fall back to the base external path
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        // On iOS, saving to 'Downloads' isn't standard via path_provider.
        // Saving to ApplicationDocumentsDirectory is more common and accessible via Files app.
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        debugPrint(
          "Could not determine suitable directory for saving debug audio.",
        );
        return null;
      }

      // Ensure the directory exists (especially the Downloads subdirectory on Android)
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Create a unique filename
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'attendance_audio_$timestamp.wav';
      final String filePath = '${directory.path}/$fileName';

      // Write the file
      final File audioFile = File(filePath);
      await audioFile.writeAsBytes(audioBytes);

      debugPrint("Debug audio saved to: $filePath");
      return filePath; // Return the path
    } catch (e) {
      debugPrint("Error saving debug audio: $e");
      return null; // Return null on failure
    }
  }

  // --- Main Handler Method ---
  Future<void> handleAttendance({
    // Context and State Management Callbacks from the Screen
    required BuildContext context,
    required Function(VoidCallback fn) setState,
    required Map<String, bool> isMarkingLecture, // Pass the state map
    required Map<String, String> markingInitiator, // Pass the state map
    required Function(String lectureSlug)
    resetMarkingState, // Callback to reset state
    // Data required for the operation
    required dynamic lecture,
    required String? currentAccessToken,
    required String? currentDeviceId,
    String? reason, // Optional reason for manual marking
    // Callbacks for UI feedback and actions owned by the Screen
    required Function(
      String message, {
      bool isError,
      Color? backgroundColor,
      Duration duration,
    })
    showSnackbar,
    required Function(String message) handleCriticalError,
    required Function({bool showLoading})
    fetchTimetableData, // Callback to refresh UI
    required Function() getAndStoreDeviceId, // Callback to refetch device ID
    required Function() loadAccessToken, // Callback to reload token
  }) async {
    final String lectureSlug = lecture['slug'] ?? '';
    if (lectureSlug.isEmpty) {
      showSnackbar("Invalid lecture data.", isError: true);
      return;
    }
    // Check if already marking this specific lecture
    if (isMarkingLecture[lectureSlug] == true) return;

    final String initiator = reason == null ? 'auto' : 'manual';

    // --- Initial Checks ---
    // 1. Developer Mode / Debugger Check
    bool devModeEnabledNow = false;
    bool debuggerAttachedNow = false;
    try {
      final checksresults = await securityService.runAllChecks();
      devModeEnabledNow = checksresults['isDeveloperModeEnabled'] ?? false;
      debuggerAttachedNow = checksresults['isDebuggerAttached'] ?? false;
    } catch (e) {
      debugPrint("Error re-checking dev mode and debugger: $e");
    }

    if (devModeEnabledNow || debuggerAttachedNow) {
      debugPrint("Security check failed at time of marking. Aborting.");
      handleCriticalError(
        "Attendance marking disabled while ${devModeEnabledNow ? "Developer Options are active." : "Debugger is Attached."}",
      );
      return;
    }

    // 2. Connectivity Check
    final bool connected = await NetwrokUtils.isConnected();
    if (!connected) {
      showSnackbar(
        "No internet connection. Please connect and try again.",
        isError: true,
      );
      return;
    }

    // 3. Token & Device ID Check
    String? currentToken =
        currentAccessToken; // Use local var for potential refresh
    String? currentDevId = currentDeviceId; // Use local var

    if (currentToken == null || currentToken.isEmpty) {
      showSnackbar(
        "Authentication error. Please restart the app.",
        isError: true,
      );
      return;
    }
    if (currentDevId == null || currentDevId.isEmpty) {
      showSnackbar("Device Identification error. Retrying...", isError: true);
      await getAndStoreDeviceId(); // Call the screen's method to refetch/store
      // Re-read the device ID from where the screen stores it (assuming getAndStoreDeviceId updates it)
      // This part is slightly awkward - ideally the screen passes the updated ID back,
      // or the DeviceIDService provides a direct getter. Assuming getAndStoreDeviceId updates a provider/state.
      // For simplicity here, we'll assume the calling screen needs to manage passing the updated ID if this happens.
      // Let's show an error if it's still null after retry.
      try {
        currentDevId = await deviceIDService.getUniqueDeviceId();
      } catch (_) {} // Try getting again
      if (currentDevId == null || currentDevId.isEmpty) {
        showSnackbar(
          "Could not get Device ID. Cannot mark attendance.",
          isError: true,
        );
        return;
      }
    }

    // --- Set Loading State ---
    setState(() {
      isMarkingLecture[lectureSlug] = true;
      markingInitiator[lectureSlug] = initiator;
    });

    // --- Conditional Data Collection ---
    AttendanceDataResult? dataResult;
    if (initiator == 'auto') {
      showSnackbar(
        "Collecting surrounding data please do not close the app...",
        isError: false,
        duration: const Duration(seconds: 8),
      );
      dataResult = await dataCollector.collectData(
        recordingDuration: const Duration(seconds: 5),
      );
      // Hide immediately after await returns, before processing result
      if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!context.mounted) {
        resetMarkingState(lectureSlug);
        return;
      }

      // Handle data collection failure
      if (dataResult.status != AttendanceDataStatus.success) {
        // ... (Error handling logic with switch statement and showPermissionDialog/showSnackbar callbacks) ...
        String errorMsg =
            dataResult.errorMessage ?? 'Failed to collect necessary data.';
        bool showSettingsDialog = false;
        String dialogTitle = 'Permission Required';
        String dialogContent = '';
        AppSettingsType settingsType = AppSettingsType.settings;
        switch (dataResult.status) {
          case AttendanceDataStatus.locationPermissionDeniedForever:
            dialogTitle = 'Location Permission';
            dialogContent =
                'Location permission has been permanently denied. Please enable it in app settings to mark attendance.';
            settingsType = AppSettingsType.location;
            showSettingsDialog = true;
            break;
          case AttendanceDataStatus.microphonePermissionDeniedForever:
            dialogTitle = 'Microphone Permission';
            dialogContent =
                'Microphone permission has been permanently denied. Please enable it in app settings for attendance verification.';
            settingsType = AppSettingsType.settings;
            showSettingsDialog = true;
            break;
          case AttendanceDataStatus.locationServiceDisabled:
            dialogTitle = 'Location Services Disabled';
            dialogContent =
                'Location services are turned off on your device. Please enable them in settings to mark attendance.';
            settingsType = AppSettingsType.location;
            showSettingsDialog = true;
            break;
          case AttendanceDataStatus.locationPermissionDenied:
            errorMsg = 'Location permission is required.';
            break;
          case AttendanceDataStatus.microphonePermissionDenied:
            errorMsg = 'Microphone permission is required.';
            break;
          case AttendanceDataStatus.locationTimeout:
            errorMsg = 'Could not get location/audio in time.';
            break;
          case AttendanceDataStatus.locationIsMocked:
            errorMsg = 'Mock locations are not allowed.';
            break;
          case AttendanceDataStatus.recordingError:
            errorMsg = 'Failed to record audio.';
            break;
          case AttendanceDataStatus.locationError:
            errorMsg = 'Could not determine location.';
            break;
          default:
            break;
        }
        if (showSettingsDialog) {
          DialogUtils.showPermissionSettingsSheet(
            context: context, // Pass the context
            title: dialogTitle,
            content: dialogContent,
            settingsType: settingsType,
            onErrorSnackbar:
                showSnackbar, // Pass the screen's snackbar function for error handling
          );
        } else {
          showSnackbar(errorMsg, isError: true);
        }
        resetMarkingState(lectureSlug);
        return;
      }
      if (dataResult.locationData == null ||
          dataResult.audioBytes == null ||
          dataResult.recordingStartTimeMillis == null) {
        showSnackbar('Collected data is incomplete.', isError: true);
        resetMarkingState(lectureSlug);
        return;
      }
      final savedPath = await _saveAudioForDebug(dataResult!.audioBytes!);
      if (savedPath != null && context.mounted) {
        // Show snackbar indicating save location (optional now)
        showSnackbar(
          "Debug audio saved. Preparing share...",
          isError: false,
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 2),
        );
      }
    }

    // --- Prepare and Execute API Call ---
    showSnackbar(
      initiator == 'auto' ? "Marking attendance..." : "Submitting request...",
      isError: false,
    );
    String encodedDeviceId;
    try {
      encodedDeviceId = base64Encode(
        utf8.encode(currentDevId),
      ); // Use local var
    } catch (e) {
      showSnackbar('Failed to prepare device identifier.', isError: true);
      resetMarkingState(lectureSlug);
      return;
    }

    // Call the internal API request helper
    await _makeApiRequestWithRetryInternal(
      // Pass necessary callbacks and data
      context: context, // Needed for navigation on logout
      setState: setState,
      isMarkingLecture: isMarkingLecture,
      markingInitiator: markingInitiator,
      resetMarkingState: resetMarkingState,
      showSnackbar: showSnackbar,
      fetchTimetableData: fetchTimetableData,
      loadAccessToken: loadAccessToken, // Pass callback
      authService: authService, // Pass service instance
      // Request specific data
      lectureSlug: lectureSlug,
      initiator: initiator,
      url:
          initiator == 'auto'
              ? '$backendBaseUrl/api/manage/session/mark_attendance_for_student/'
              : '$backendBaseUrl/api/manage/session/mark_for_regulization/',
      initialAccessToken: currentToken, // Pass current token
      deviceIdEncoded: encodedDeviceId,
      locationData: dataResult?.locationData,
      audioBytes: dataResult?.audioBytes,
      recordingStartTimeMillis: dataResult?.recordingStartTimeMillis,
      reason: reason,
    );

    // Hide the "Marking/Submitting" snackbar
    if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // State reset is handled within _makeApiRequestWithRetryInternal's finally block
  }

  // --- Internal Helper for API Request with Retry Logic ---
  // Made private to the service class
  Future<void> _makeApiRequestWithRetryInternal({
    // Callbacks & Services needed
    required BuildContext context,
    required Function(VoidCallback fn)
    setState, // Needed if retry updates UI directly (unlikely here)
    required Map<String, bool>
    isMarkingLecture, // Needed? Only if retry changes this map? Usually not.
    required Map<String, String>
    markingInitiator, // Needed? Only if retry changes this map? Usually not.
    required Function(String lectureSlug) resetMarkingState,
    required Function(
      String message, {
      bool isError,
      Color? backgroundColor,
      Duration duration,
    })
    showSnackbar,
    required Function({bool showLoading}) fetchTimetableData,
    required Function()
    loadAccessToken, // Callback to reload token on screen state
    required AuthService authService, // Service instance
    // Request specific data
    required String lectureSlug,
    required String initiator,
    required String url,
    required String initialAccessToken,
    required String deviceIdEncoded,
    LocationData? locationData,
    Uint8List? audioBytes,
    int? recordingStartTimeMillis,
    String? reason,
  }) async {
    String currentToken = initialAccessToken; // Token for the current attempt

    // --- Function to build the request ---
    http.BaseRequest buildRequest(String token) {
      bool isMultipart = initiator == 'auto';
      if (isMultipart) {
        assert(
          locationData != null &&
              audioBytes != null &&
              recordingStartTimeMillis != null,
        );
        final req = http.MultipartRequest('POST', Uri.parse(url));
        req.headers['Authorization'] = 'Bearer $token';
        req.fields['device_id'] = deviceIdEncoded;
        req.fields['latitude'] = locationData!.latitude.toString();
        req.fields['longitude'] = locationData.longitude.toString();
        req.fields['lecture_slug'] = lectureSlug;
        req.fields['start_time'] =
            recordingStartTimeMillis!
                .toString(); // Use correct field name from previous step
        req.files.add(
          http.MultipartFile.fromBytes(
            'audio',
            audioBytes!,
            filename: 'attendance_audio.wav',
          ),
        ); // Use correct field name
        return req;
      } else {
        final req = http.Request('POST', Uri.parse(url));
        req.headers['Authorization'] = 'Bearer $token';
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode({
          'lecture_slug': lectureSlug,
          'device_id': deviceIdEncoded,
          if (reason != null) 'regulization_commet': reason,
        });
        return req;
      }
    }
    // --- End buildRequest function ---

    // --- Define function for processing successful response ---
    // Avoids duplicating success logic for initial and retry attempts
    Future<void> processSuccessResponse(String responseBody) async {
      final responseData = jsonDecode(responseBody);
      if (responseData['data'] == true && responseData['code'] == 100) {
        showSnackbar(
          initiator == 'auto'
              ? 'Attendance marked!'
              : 'Manual request submitted!',
          isError: false,
        );
        await fetchTimetableData(showLoading: false); // Refresh silently
      } else {
        throw Exception(
          responseData['message'] ??
              (initiator == 'auto' ? 'Failed to mark' : 'Failed to submit'),
        );
      }
    }
    // --- End processSuccessResponse function ---

    try {
      // --- Initial Attempt ---
      http.BaseRequest request = buildRequest(currentToken);
      debugPrint("Attempting API Request (Initial)");
      http.StreamedResponse streamedResponse = await (request
                  is http.MultipartRequest
              ? request.send()
              : http.Client().send(request))
          .timeout(const Duration(seconds: 20));

      if (!context.mounted) return;

      final http.Response response = await http.Response.fromStream(
        streamedResponse,
      );

      final int statusCode = response.statusCode;
      final String responseBody = response.body;

      debugPrint("API Response Status (Initial): $statusCode");
      // Avoid printing large bodies in production logs
      // debugPrint("API Response Body (Initial): $responseBody");

      // --- Handle Response ---
      if (statusCode == 200 || statusCode == 201) {
        await processSuccessResponse(responseBody); // Process success
      } else if (statusCode == 401 || statusCode == 403) {
        // --- Handle Auth Error & Retry ---
        debugPrint("Received 401/403. Attempting token refresh...");
        showSnackbar(
          "Session may have expired. Refreshing...",
          isError: false,
          backgroundColor: Colors.orange,
        ); // Inform user
        final refreshResult = await authService.attemptTokenRefresh();

        if (refreshResult == RefreshStatus.success) {
          debugPrint("Refresh successful. Retrying original request...");
          // Reload token via callback - This updates the token in the SCREEN'S state
          await loadAccessToken();
          String? newAccessToken =
              await loadAccessToken(); // Need this method in AuthService

          if (newAccessToken == null || newAccessToken.isEmpty) {
            // If AuthService can't provide it, try reading from storage again (less ideal)
            // newAccessToken = await FlutterSecureStorage().read(key: 'accessToken');
            if (newAccessToken == null || newAccessToken.isEmpty) {
              throw Exception(
                'Refresh reported success but could not retrieve new token.',
              );
            }
          }
          currentToken = newAccessToken; // Update token for retry

          // Build retry request with NEW token
          http.BaseRequest retryRequest = buildRequest(currentToken);
          debugPrint("Attempting API Request (Retry)");

          // Send Retry Request
          http.StreamedResponse retryStreamedResponse = await (retryRequest
                      is http.MultipartRequest
                  ? retryRequest.send()
                  : http.Client().send(retryRequest))
              .timeout(const Duration(seconds: 20));

          if (!context.mounted) return;

          final http.Response retryResponse = await http.Response.fromStream(
            retryStreamedResponse,
          );

          int retryStatusCode = retryResponse.statusCode;
          String retryResponseBody = retryResponse.body;

          debugPrint("API Response Status (Retry): $retryStatusCode");
          // debugPrint("API Response Body (Retry): $retryResponseBody");

          // Handle Retry Response
          if (retryStatusCode == 200 || retryStatusCode == 201) {
            await processSuccessResponse(retryResponseBody); // Process success
          } else {
            // Retry also failed (could be another 401 or different error)
            String retryErrorMsg = 'Failed after refresh';
            try {
              final d = jsonDecode(retryResponseBody);
              retryErrorMsg = d['message'] ?? retryErrorMsg;
            } catch (_) {}
            // Decide if we should logout here or just show error
            if (retryStatusCode == 401 || retryStatusCode == 403) {
              debugPrint("Retry failed with 401/403. Logging out.");
              await authService.clearTokens();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => LoginScreen(
                          initialMessage:
                              'Session expired. Please log in again.',
                        ),
                  ),
                  (route) => false,
                );
              }
              // Don't throw exception if navigating away
              return; // Exit after navigation
            } else {
              throw Exception('$retryErrorMsg (Status: $retryStatusCode)');
            }
          }
        } else {
          // Refresh failed, logout
          debugPrint("Refresh failed. Logging out.");
          await authService.clearTokens();
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder:
                    (context) => LoginScreen(
                      initialMessage: 'Session expired. Please log in again.',
                    ),
              ),
              (route) => false,
            );
          }
          return; // Exit after navigation
        }
      } else {
        // Other non-200, non-401/403 errors on initial attempt
        String errorMessage = 'Server error';
        try {
          final d = jsonDecode(responseBody);
          errorMessage = "${d['message']}";
        } catch (_) {}
        throw Exception('$errorMessage (Status: $statusCode)');
      }
    } catch (e) {
      // Catch all errors from API call, refresh, or retry
      debugPrint('API Request/Retry Error: ${e.toString()}');
      showSnackbar(
        e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Something went wrong. Please try again.',
        isError: true,
      );
    } finally {
      // Always reset the marking state for this specific lecture via callback
      resetMarkingState(lectureSlug);
    }
  }
} // End of MarkAttendaceService

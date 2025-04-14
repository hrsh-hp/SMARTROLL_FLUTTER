import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:smartroll/Screens/login_screen.dart';
import 'package:smartroll/Screens/manual_marking_dialouge.dart'; // Ensure this path is correct
import 'package:smartroll/utils/constants.dart';
import 'package:smartroll/utils/attendace_data_collector.dart';
import 'package:smartroll/utils/auth_service.dart';
import 'package:smartroll/utils/device_id_service.dart'; // Ensure this path is correct
import 'error_screen.dart'; // Ensure this path is correct
import 'package:path_provider/path_provider.dart';

// --- Centralized Configuration ---
const String _backendBaseUrl = backendBaseUrl;

class AttendanceMarkingScreen extends StatefulWidget {
  const AttendanceMarkingScreen({super.key});

  @override
  State<AttendanceMarkingScreen> createState() =>
      _AttendanceMarkingScreenState();
}

class _AttendanceMarkingScreenState extends State<AttendanceMarkingScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final deviceIdService = DeviceIDService();
  final SecurityService _securityService = SecurityService();
  final AttendanceDataCollector _dataCollector = AttendanceDataCollector();

  // --- State Variables (Original Names) ---
  bool _isLoadingTimetable = true;
  String? _fetchErrorMessage;
  List<dynamic> _timetableData = [];
  String? _deviceId;
  String? _accessToken;

  // State for button disabling and loading indicators per lecture
  final Map<String, bool> _isMarkingLecture = {};
  final Map<String, String> _markingInitiator = {};
  // Animation controller for the shimmer effect
  late AnimationController _shimmerController;
  late Animation<double> _fadeAnimation;
  // ---------------------

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.3, end: 0.9).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut, // Smooth transition
      ),
    );
    _shimmerController.repeat(reverse: true);
    _initializeAndFetchData();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

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
        String downloadsPath = '${directory?.path}/Downloads';
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
      final String timestamp = DateTime.now().millisecondsSinceEpoch as String;
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

  Future<void> _loadAccessToken() async {
    // Use actual storage read
    _accessToken = await secureStorage.read(key: 'accessToken');
    debugPrint("Access token loaded: ${_accessToken != null}");
  }

  // --- Initialization and Data Fetching (Unchanged from previous safe version) ---
  Future<void> _initializeAndFetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTimetable = true;
      _fetchErrorMessage = null;
    });
    await _loadAccessToken();
    if (_accessToken == null || _accessToken!.isEmpty) {
      _handleCriticalError(
        "Authentication credentials missing. Please login again.",
      );
      return;
    }
    await _getAndStoreDeviceId();
    if (!mounted) return;
    await _fetchTimetableData(showLoading: false);
    if (mounted) {
      setState(() {
        _isLoadingTimetable = false;
      });
    }
  }

  Future<void> _getAndStoreDeviceId() async {
    try {
      _deviceId = await deviceIdService.getUniqueDeviceId();
      debugPrint("Device ID: $_deviceId");
    } catch (e) {
      debugPrint("Error getting device ID: $e");
    }
  }

  Future<void> _fetchTimetableData({bool showLoading = true}) async {
    final bool connected = await NetwrokUtils.isConnected();
    if (!mounted) return;
    if (!connected) {
      _handleCriticalError(
        "No internet connection. Please connect and try again.",
      );
      if (showLoading && _isLoadingTimetable) {
        setState(() {
          _isLoadingTimetable = false;
        });
      }
      return; // Stop execution
    }

    if (showLoading && mounted) {
      setState(() {
        _isLoadingTimetable = true;
        _fetchErrorMessage = null;
      });
    }
    if (_accessToken == null) {
      if (mounted) {
        _handleFetchError("Authentication credentials missing unexpectedly");
      }
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$_backendBaseUrl/api/manage/get_timetable_for_student'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);
        if (decodedBody['error'] == false && decodedBody['data'] is List) {
          setState(() {
            _timetableData = decodedBody['data'];
            _fetchErrorMessage = null;
          });
        } else {
          throw Exception(decodedBody['message'] ?? 'Failed to parse data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleCriticalError('Authentication failed. Please restart the app.');
      } else {
        String errorMsg = 'Failed to load timetable.';
        try {
          final decodedError = jsonDecode(response.body);
          if (decodedError['message'] != null) {
            errorMsg = decodedError['message'];
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (mounted) {
        _handleFetchError("Could not fetch timetable. Please try again.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
      }
    }
  }

  // --- Helper Function for Permission Dialog ---
  void _showPermissionDialog(
    String title,
    String content,
    AppSettingsType settingsType,
  ) {
    if (!mounted) return;

    showDialog(
      context: context, // Use the widget's context
      barrierDismissible: false, // User must interact with the dialog
      builder:
          (BuildContext dialogContext) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(title),
            content: Text(content, style: TextStyle(color: Colors.grey[300])),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed:
                    () => Navigator.of(dialogContext).pop(), // Close the dialog
              ),
              TextButton(
                child: const Text('Open Settings'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close the dialog first
                  // Use the app_settings package to open the relevant settings screen
                  AppSettings.openAppSettings(type: settingsType).catchError((
                    error,
                  ) {
                    // Optional: Handle error if settings cannot be opened
                    if (mounted) {
                      _showSnackbar("Could not open settings.", isError: true);
                    }
                  });
                },
              ),
            ],
          ),
    );
  }

  // --- Attendance Marking Logic ---
  Future<void> _handleMarkAttendance(dynamic lecture, {String? reason}) async {
    final String lectureSlug = lecture['slug'];
    if (_isMarkingLecture[lectureSlug] == true) return;

    final String initiator = reason == null ? 'auto' : 'manual';
    if (!mounted) return;

    // 1. Developer Mode Check (at time of marking)
    bool devModeEnabledNow = false;
    bool debuggerAttachedNow = false;
    try {
      // Assuming you have access to SecurityService instance (_securityService)
      final checksresults = await _securityService.runAllChecks();
      devModeEnabledNow = checksresults['isDeveloperModeEnabled'] ?? false;
      debuggerAttachedNow = checksresults['isDebuggerAttached'] ?? false;
    } catch (e) {
      debugPrint("Error re-checking dev mode and debugger: $e");
    }

    if (devModeEnabledNow && !debuggerAttachedNow) {
      debugPrint("Developer mode detected at time of marking. Aborting.");
      if (mounted) {
        // _showSnackbar(
        //   "Attendance marking disabled while Developer Options are active.",
        //   isError: true,
        // );
        _handleCriticalError(
          "Attendance marking disabled while ${devModeEnabledNow ? "Developer Options are active." : "Debugger is Attached."}",
        );
      }
      // _resetMarkingState(lectureSlug);
      return; // Stop the marking process
    }

    // 2. Connectivity Check
    final bool connected = await NetwrokUtils.isConnected();
    if (!connected) {
      _handleCriticalError(
        "No internet connection. Please connect and try again.",
      );
      return; // Stop execution
    }

    // 3. Token & Device ID Check
    if (_accessToken == null) {
      _showSnackbar("Authentication error.", isError: true);
      _resetMarkingState(lectureSlug);
      return;
    }
    if (_deviceId == null) {
      _showSnackbar("Device Identification error. Retrying...", isError: true);
      await _getAndStoreDeviceId();
      if (!mounted) {
        _resetMarkingState(lectureSlug);
        return;
      }
      if (_deviceId == null) {
        _showSnackbar("Could not get Device ID.", isError: true);
        _resetMarkingState(lectureSlug);
        return;
      }
    }

    //4. collecting loaction and audio
    setState(() {
      _isMarkingLecture[lectureSlug] = true;
      _markingInitiator[lectureSlug] = initiator;
    });

    AttendanceDataResult? dataResult;
    if (initiator == 'auto') {
      dataResult = await _dataCollector.collectData(
        recordingDuration: const Duration(seconds: 10),
      );
      _showSnackbar(
        "Collecting surrounding data please do not close the app...",
        isError: false,
        duration: const Duration(seconds: 12),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).hideCurrentSnackBar(); // Hide collecting message

      if (!mounted) {
        _resetMarkingState(lectureSlug);
        return;
      }

      // Handle data collection failure
      if (dataResult.status != AttendanceDataStatus.success) {
        String errorMsg =
            dataResult.errorMessage ?? 'Failed to collect necessary data.';
        bool showSettingsDialog = false;
        String dialogTitle = 'Permission Required';
        String dialogContent = '';
        AppSettingsType settingsType = AppSettingsType.settings; // Default

        switch (dataResult.status) {
          // --- Cases where Settings Dialog is appropriate ---
          case AttendanceDataStatus.locationPermissionDeniedForever:
            dialogTitle = 'Location Permission Required';
            dialogContent =
                'Location permission has been permanently denied. Please enable it in app settings to mark attendance.';
            settingsType =
                AppSettingsType.location; // Go directly to location settings
            showSettingsDialog = true;
            break;
          case AttendanceDataStatus.microphonePermissionDeniedForever:
            dialogTitle = 'Microphone Permission Required';
            dialogContent =
                'Microphone permission has been permanently denied. Please enable it in app settings for attendance verification.';
            // No specific microphone type, use general settings
            settingsType = AppSettingsType.settings;
            showSettingsDialog = true;
            break;
          case AttendanceDataStatus.locationServiceDisabled:
            dialogTitle = 'Location Services Disabled';
            dialogContent =
                'Location services are turned off on your device. Please enable them in settings to mark attendance.';
            settingsType = AppSettingsType.location; // Go to location settings
            showSettingsDialog = true;
            break;

          // --- Cases where a Snackbar is sufficient ---
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
          default: // Includes unknownError
            break; // Use the default errorMsg
        }

        // Show Dialog or Snackbar based on the flag
        if (showSettingsDialog) {
          _showPermissionDialog(dialogTitle, dialogContent, settingsType);
        } else {
          _showSnackbar(errorMsg, isError: true);
        }

        _resetMarkingState(lectureSlug); // Reset state after handling error
        return; // Stop the process
      }
      // Check null safety again
      if (dataResult.locationData == null || dataResult.audioBytes == null) {
        _showSnackbar('Collected data is incomplete.', isError: true);
        _resetMarkingState(lectureSlug);
        return;
      }
    }
    if (initiator == 'auto' && kDebugMode) {
      // We know dataResult and dataResult.audioBytes are non-null here
      final savedPath = await _saveAudioForDebug(
        dataResult!.audioBytes!,
      ); // Use ! safely here because of the checks above
      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Debug audio saved:"),
                const SizedBox(height: 4),
                SelectableText(savedPath, style: const TextStyle(fontSize: 12)),
              ],
            ),
            duration: const Duration(seconds: 10),
            backgroundColor: Colors.teal,
          ),
        );
      } else if (mounted) {
        _showSnackbar(
          "Could not save debug audio.",
          isError: true,
          backgroundColor: Colors.orange,
        );
      }
    }
    _showSnackbar(
      initiator == 'auto' ? "Marking attendance..." : "Submitting request...",
      isError: false,
    );
    try {
      final String url =
          initiator == 'auto'
              ? '$backendBaseUrl/api/manage/session/mark_attendance_for_student/'
              : '$backendBaseUrl/api/manage/session/mark_for_regulization/';
      await _makeApiRequestWithRetry(
        lectureSlug: lectureSlug,
        initiator: initiator,
        url: url,
        accessToken: _accessToken!,
        deviceIdEncoded: base64Encode(utf8.encode(_deviceId!)),
        locationData: dataResult?.locationData, // Null for manual
        audioBytes: dataResult?.audioBytes, // Null for manual
        reason: reason, // Null for auto
      );
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Reset state is handled within _makeApiRequestWithRetry's finally block
    } catch (e) {
      debugPrint('Error: ${e.toString()}');
      _showSnackbar('Something went wrong. Please try again.', isError: true);
    } finally {
      _resetMarkingState(lectureSlug);
    }
  }

  // --- Helper Function for API Request with Retry Logic ---
  Future<void> _makeApiRequestWithRetry({
    required String lectureSlug,
    required String initiator,
    required String url,
    required String accessToken,
    required String deviceIdEncoded,
    LocationData? locationData, // Nullable
    Uint8List? audioBytes, // Nullable
    String? reason, // Nullable
  }) async {
    http.BaseRequest request;
    bool isMultipart = initiator == 'auto';

    // --- Function to build the request (used for initial and retry) ---
    http.BaseRequest buildRequest(String currentToken) {
      if (isMultipart) {
        final multipartRequest = http.MultipartRequest('POST', Uri.parse(url));
        multipartRequest.headers['Authorization'] = 'Bearer $currentToken';
        multipartRequest.fields['device_id'] = deviceIdEncoded;
        multipartRequest.fields['latitude'] = locationData!.latitude.toString();
        multipartRequest.fields['longitude'] =
            locationData.longitude.toString();
        multipartRequest.fields['lecture_slug'] = lectureSlug;
        // Add audio file
        multipartRequest.files.add(
          http.MultipartFile.fromBytes(
            'audio',
            audioBytes!,
            filename: 'attendance_audio.wav',
          ),
        );
        return multipartRequest;
      } else {
        // Standard JSON POST for manual request
        final jsonRequest = http.Request('POST', Uri.parse(url));
        jsonRequest.headers['Authorization'] = 'Bearer $currentToken';
        jsonRequest.headers['Content-Type'] = 'application/json';
        final Map<String, dynamic> requestBody = {
          'lecture_slug': lectureSlug,
          'device_id': deviceIdEncoded,
          if (reason != null) 'regulization_commet': reason,
        };
        jsonRequest.body = jsonEncode(requestBody);
        return jsonRequest;
      }
    }
    // --- End buildRequest function ---

    try {
      request = buildRequest(accessToken); // Build initial request

      // --- Send Request (Initial Attempt) ---
      final http.StreamedResponse streamedResponse = await (request
                  is http.MultipartRequest
              ? request.send()
              : http.Client().send(
                request,
              ) // Need Client().send for http.Request
              )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final http.Response response = await http.Response.fromStream(
        streamedResponse,
      );

      final int statusCode = response.statusCode;
      final String responseBody = response.body;

      debugPrint("API Response Status: $statusCode");
      debugPrint("API Response Body: $responseBody");

      // --- Handle Response ---
      if (statusCode == 200 || statusCode == 201) {
        // Success
        final responseData = jsonDecode(responseBody);
        if (responseData['data'] == true && responseData['code'] == 100) {
          _showSnackbar(
            initiator == 'auto'
                ? 'Attendance marked!'
                : 'Manual request submitted!',
            isError: false,
          );
          await _fetchTimetableData(showLoading: false); // Refresh silently
        } else {
          throw Exception(
            responseData['message'] ??
                (initiator == 'auto' ? 'Failed to mark' : 'Failed to submit'),
          );
        }
      } else if (statusCode == 401 || statusCode == 403) {
        // --- Handle Auth Error & Retry ---
        debugPrint("Received 401/403. Attempting token refresh...");
        final refreshResult = await _authService.attemptTokenRefresh();

        if (refreshResult == RefreshStatus.success) {
          debugPrint("Refresh successful. Retrying original request...");
          await _loadAccessToken(); // Reload the new token into _accessToken
          if (_accessToken == null || _accessToken!.isEmpty) {
            throw Exception(
              'Refresh reported success but new token is missing.',
            );
          }

          // Build retry request with NEW token
          final retryRequest = buildRequest(_accessToken!);

          // Send Retry Request
          final http.StreamedResponse retryStreamedResponse =
              await (retryRequest is http.MultipartRequest
                      ? retryRequest.send()
                      : http.Client().send(retryRequest))
                  .timeout(const Duration(seconds: 30));

          if (!mounted) return;

          final int retryStatusCode = retryStreamedResponse.statusCode;
          final String retryResponseBody =
              await retryStreamedResponse.stream.bytesToString();

          debugPrint("API Retry Response Status: $retryStatusCode");
          debugPrint("API Retry Response Body: $retryResponseBody");

          // Handle Retry Response
          if (retryStatusCode == 200 || retryStatusCode == 201) {
            final retryResponseData = jsonDecode(retryResponseBody);
            if (retryResponseData['data'] == true &&
                retryResponseData['code'] == 100) {
              _showSnackbar(
                initiator == 'auto'
                    ? 'Attendance marked!'
                    : 'Manual request submitted!',
                isError: false,
              );
              await _fetchTimetableData(showLoading: false);
            } else {
              throw Exception(
                retryResponseData['message'] ?? 'Failed after refresh',
              );
            }
          } else {
            // Retry also failed
            throw Exception(
              'Failed to mark attendance after refresh (Status: $retryStatusCode).',
            );
          }
        } else {
          // Refresh failed, logout
          debugPrint("Refresh failed. Logging out.");
          await _authService.clearTokens();
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder:
                    (context) => LoginScreen(
                      initialMessage: 'Session expired. Please log in again.',
                    ),
              ), // Pass message
              (route) => false,
            );
          }
          // No need to throw exception here, navigation handles it
        }
      } else {
        // Other non-200, non-401/403 errors
        String errorMessage = 'Server error';
        try {
          final responseData = jsonDecode(responseBody);
          errorMessage = "${responseData['message']}";
        } catch (_) {
          /* Ignore if not JSON */
        }
        throw Exception('$errorMessage (Status: $statusCode)');
      }
    } catch (e) {
      // Catch all errors from API call, refresh, or retry
      debugPrint('API Request/Retry Error: ${e.toString()}');
      _showSnackbar(
        e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Something went wrong. Please try again.',
        isError: true,
      );
    } finally {
      // Always reset the marking state for this specific lecture
      _resetMarkingState(lectureSlug);
    }
  }

  void _resetMarkingState(String lectureSlug) {
    if (mounted) {
      setState(() {
        _isMarkingLecture.remove(lectureSlug);
        _markingInitiator.remove(lectureSlug);
      });
    }
  }
  // ------------------------------

  // --- Manual Marking Dialog Call (ADDED ROBUSTNESS) ---
  void _showManualMarkingDialog(dynamic lecture) {
    // Defensive check for lecture structure before accessing nested keys
    String subjectName = 'Unknown Subject';
    try {
      // Check if keys exist before accessing them
      if (lecture != null &&
          lecture['subject'] is Map &&
          lecture['subject']['subject_map'] is Map &&
          lecture['subject']['subject_map']['subject_name'] != null) {
        subjectName = lecture['subject']['subject_map']['subject_name'];
      } else {
        debugPrint(
          "Warning: Could not extract subject name from lecture object: $lecture",
        );
      }
    } catch (e) {
      debugPrint("Error extracting subject name: $e. Lecture object: $lecture");
      // Keep default subjectName
    }
    showDialog(
      context: context,
      barrierDismissible: false, // Good practice while submitting
      builder:
          (context) => ManualMarkingDialog(
            subjectName: subjectName, // Pass the safely extracted name
            onSubmit: (reason) {
              // Navigator.of(context).pop(); // Close dialog
              // Call the original handler, passing the original lecture object
              _handleMarkAttendance(lecture, reason: reason);
            },
          ),
    ).catchError((error) {
      // Catch potential errors during dialog build/display
      debugPrint("Error showing dialog: $error");
      _showSnackbar("Could not open manual marking dialog.", isError: true);
    });
  }
  // ------------------------------

  // // --- UI Helpers LOGOUT(Unchanged) ---
  // void _handleLogout() async {
  //   await secureStorage.deleteAll();
  //   if (mounted) {
  //     Navigator.pushAndRemoveUntil(
  //       context,
  //       MaterialPageRoute(builder: (context) => const SplashScreen()),
  //       (route) => false,
  //     );
  //   }
  // }

  void _handleFetchError(String message) {
    if (mounted) {
      setState(() {
        _fetchErrorMessage = message;
        _isLoadingTimetable = false;
        _timetableData = [];
      });
    }
  }

  void _handleCriticalError(String message) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ErrorScreen(message: message)),
      );
    }
  }

  void _showSnackbar(
    String message, {
    bool isError = true,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              backgroundColor ??
              (isError ? Colors.red.shade700 : Colors.green.shade700),
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
    }
  }

  String _formatTime(String timeString) {
    try {
      if (timeString.contains('.')) timeString = timeString.split('.').first;
      final parsedTime = DateFormat("HH:mm:ss").parse(timeString);
      return DateFormat("h:mm a").format(parsedTime);
    } catch (e) {
      debugPrint("Error formatting time '$timeString': $e");
      return timeString;
    }
  }
  // ----------------

  // --- Build Method (AppBar Unchanged) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          // height: kToolbarHeight - 2,
          width: MediaQuery.of(context).size.width * 0.4, //100
          child: Image.asset('assets/LOGO.webp', fit: BoxFit.contain),
        ), // Use the logo image
        // leading: IconButton(
        //   tooltip: "Refresh Schedule", // Add tooltip for accessibility
        //   icon: const Icon(Icons.refresh),
        //   // Use the same onPressed logic as before
        //   onPressed:
        //       _isLoadingTimetable || _isMarkingLecture.containsValue(true)
        //           ? null
        //           : () => _fetchTimetableData(showLoading: true),
        // ),
        // actions: [
        //   IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout),
        // ],
      ),
      body: _buildBodyWithDividers(), // Call the new body builder
    );
  }

  // --- Body Builder with Dividers and Styled Header ---
  Widget _buildBodyWithDividers() {
    if (_isLoadingTimetable) {
      return _buildLoadingShimmer();
    }
    if (_fetchErrorMessage != null) {
      return _buildErrorState();
    }

    List<Map<String, dynamic>> flattenedLectures = [];
    String? previousBranchSlug;

    for (var streamGroup in _timetableData) {
      final String currentBranchName =
          streamGroup['stream']?['branch']?['branch_name'] ?? 'Unknown Branch';
      final String currentBranchSlug =
          streamGroup['stream']?['branch']?['slug'] ?? currentBranchName;
      final List<dynamic> timetables =
          streamGroup['timetables'] as List<dynamic>? ?? [];
      List<dynamic> lecturesInBranch = [];
      for (var timetable in timetables) {
        final schedule = timetable['schedule'] as Map<String, dynamic>?;
        if (schedule != null) {
          lecturesInBranch.addAll(schedule['lectures'] as List<dynamic>? ?? []);
        }
      }
      lecturesInBranch.sort((a, b) {
        try {
          final timeA = DateFormat("HH:mm:ss").parse(a['start_time']);
          final timeB = DateFormat("HH:mm:ss").parse(b['start_time']);
          return timeA.compareTo(timeB);
        } catch (e) {
          return 0;
        }
      });

      if (lecturesInBranch.isNotEmpty) {
        if (previousBranchSlug != null &&
            previousBranchSlug != currentBranchSlug) {
          flattenedLectures.add({'isDivider': true});
        }
        // Add the header item
        flattenedLectures.add({
          'isHeader': true,
          'branchName': currentBranchName,
        });
        // Add lecture items
        for (var lecture in lecturesInBranch) {
          flattenedLectures.add({'isLecture': true, 'data': lecture});
        }
        previousBranchSlug = currentBranchSlug;
      }
    }

    if (flattenedLectures.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _fetchTimetableData(showLoading: false),
      color: Colors.white,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        itemCount: flattenedLectures.length,
        itemBuilder: (context, index) {
          final item = flattenedLectures[index];

          if (item['isDivider'] == true) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 16.0,
                horizontal: 8.0,
              ),
              child: Divider(thickness: 1.5, color: Colors.grey[700]),
            );
          } else if (item['isHeader'] == true) {
            // --- MODIFIED Branch Header Rendering ---
            return Container(
              margin: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 8.0,
              ), // Adjust padding as needed
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade800, // Main background color
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  // Left Accent Chip
                  Container(
                    width: 5, // Adjust width for desired thickness
                    height:
                        24, // Adjust height to match text line height roughly
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.shade400, // Accent color
                      borderRadius: BorderRadius.circular(
                        3,
                      ), // Rounded corners for chip look
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ), // Spacing between left chip and text
                  // Branch Name - Expanded to handle wrapping/ellipsis
                  Expanded(
                    child: Text(
                      item['branchName'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign:
                          TextAlign.center, // Center text between the chips
                      softWrap: true, // Allow wrapping
                      maxLines: 3,
                      overflow:
                          TextOverflow
                              .ellipsis, // Add "..." if exceeds maxLines
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ), // Spacing between text and right chip
                  // Right Accent Chip (Mirror of the left one)
                  Container(
                    width: 5, // Match left chip width
                    height: 24, // Match left chip height
                    decoration: BoxDecoration(
                      color:
                          Colors.blueAccent.shade400, // Match left chip color
                      borderRadius: BorderRadius.circular(
                        3,
                      ), // Match left chip radius
                    ),
                  ),
                ],
              ),
            ); // --- End Modification ---
          } else if (item['isLecture'] == true) {
            // Render the lecture card using the updated builder
            return _buildLectureCard(item['data']);
          } else {
            return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  // --- Reinstated Lecture Card Builder (Similar to Original) ---
  Widget _buildLectureCard(dynamic lecture) {
    // Use original keys
    final String lectureSlug = lecture['slug'];
    final sessionData =
        lecture['session']
            as Map<String, dynamic>?; // Get the session map safely
    final attendanceData =
        sessionData?['attendances']
            as Map<String, dynamic>?; // Get attendance map safely
    // Determine status based on the new structure
    final bool isMarked = attendanceData?['is_present'] ?? false;
    final bool isManuallyMarked =
        attendanceData?['manual'] ?? false; // Might be useful later
    final bool isRegulizationRequested =
        attendanceData?['regulization_request'] ?? false; // *** NEW FLAG ***
    // final String? markingTime = attendanceData?['marking_time']; // Might be useful later

    final String? activeStatus =
        sessionData?['active']?.toString().toLowerCase(); // Get active status

    // --- Other existing data extraction (adjust paths if needed) ---
    final String subjectName =
        lecture['subject']?['subject_map']?['subject_name'] ??
        'Unknown Subject';
    final String subjectCode =
        lecture['subject']?['subject_map']?['subject_code'] ?? '';
    final String teacherName = lecture['teacher'] ?? 'N/A';
    final String classroom = lecture['classroom']?['class_name'] ?? 'N/A';
    final String lectureType =
        lecture['type']?.toString().toUpperCase() ??
        ''; // Assuming type is still top-level

    // Button states (remain the same)
    final bool isCurrentlyMarking = _isMarkingLecture[lectureSlug] ?? false;
    final String? initiator = _markingInitiator[lectureSlug];

    // Return the Card structure from your original code
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ), // Consistent padding
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Colors.grey[800]!, // Subtle border color
            width: 1.5,
          ), // Subtle border
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subjectName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          softWrap: true, // Allow text to wrap to the next line
                          maxLines: 2, // Limit to a maximum of 2 lines
                          overflow:
                              TextOverflow
                                  .ellipsis, // Add "..." if text exceeds maxLines
                        ),
                        if (subjectCode.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subjectCode,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isMarked || isManuallyMarked || isRegulizationRequested)
                    _buildAttendanceStatusChip(
                      isMarked || isManuallyMarked,
                      isRegulizationRequested,
                    ),
                  // else if (activeStatus == 'post')
                  //   _buildAttendanceStatusChip(
                  //     isMarked || isManuallyMarked,
                  //     isRegulizationRequested,
                  //   ),
                ],
              ),
              const SizedBox(height: 12),
              // Detail Rows (same as before)
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatTime(lecture['start_time'])} - ${_formatTime(lecture['end_time'])}',
                    style: TextStyle(color: Colors.grey[300], fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text(
                    teacherName,
                    style: TextStyle(color: Colors.grey[300], fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_city_outlined,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    classroom,
                    style: TextStyle(color: Colors.grey[300], fontSize: 14),
                  ),
                  if (lectureType.isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[900],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        lectureType,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Action Buttons (with correct disabling and loading)
              if (!isMarked && !isManuallyMarked) ...[
                const SizedBox(height: 16), // Space before actions/status
                // Determine what to show based on activeStatus
                _buildActionOrStatusWidget(
                  activeStatus,
                  lecture,
                  isCurrentlyMarking,
                  initiator,
                  isRegulizationRequested,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- NEW Helper Widget for Action Buttons or Status Text ---
  Widget _buildActionOrStatusWidget(
    String? activeStatus,
    dynamic lecture,
    bool isCurrentlyMarking,
    String? initiator,
    bool isRegulizationRequested,
  ) {
    final bool isMarked =
        lecture['session']?['attendances']?['is_present'] ?? false;
    if (activeStatus == 'ongoing') {
      // Show the buttons if the session is ongoing
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Mark Attendance Button
          ElevatedButton(
            onPressed:
                isMarked || isCurrentlyMarking
                    ? null
                    : () => _handleMarkAttendance(lecture),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              disabledBackgroundColor: Colors.grey.shade700,
              disabledForegroundColor: Colors.grey.shade400,
            ),
            child:
                isCurrentlyMarking && initiator == 'auto'
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                    : const Text(
                      'Mark Attendance',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
          // Manual Marking Button
          ElevatedButton(
            onPressed:
                isMarked || isCurrentlyMarking || isRegulizationRequested
                    ? null
                    : () => _showManualMarkingDialog(lecture),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              disabledBackgroundColor: Colors.grey.shade700,
              disabledForegroundColor: Colors.grey.shade400,
            ),
            child:
                isCurrentlyMarking && initiator == 'manual'
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : const Text(
                      'Manual Marking',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ],
      );
    } else {
      // return const SizedBox(height: 10); // Approx height of buttons row
      return const SizedBox.shrink(); // Or truly nothing
    }
  }

  Widget _buildAttendanceStatusChip(
    bool isPresent,
    bool isRegulizationRequested,
  ) {
    String statusText;
    Color chipColor;

    if (isPresent) {
      // If marked present, that's the final status, regardless of requests.
      statusText = 'Present';
      chipColor = Colors.green.shade700; // Consistent green
    } else {
      // If not present, check if a request is pending.
      if (isRegulizationRequested) {
        statusText = 'Pending'; // Changed from "Pandin"
        chipColor =
            Colors
                .orange
                .shade800; // Use a distinct color like orange for pending
      } else {
        // Not present and no request pending means Absent.
        statusText = 'Absent';
        chipColor = Colors.red.shade700; // Consistent red
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ), // Adjusted padding slightly
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(15), // Adjusted radius slightly
      ),
      child: Row(
        // Optional: Add an icon for clarity
        mainAxisSize: MainAxisSize.min,
        children: [
          // Optional Icon based on status
          if (isPresent)
            const Icon(
              Icons.check_circle_outline,
              size: 14,
              color: Colors.white,
            )
          else if (isRegulizationRequested)
            const Icon(
              Icons.hourglass_top_rounded,
              size: 14,
              color: Colors.white,
            )
          else
            const Icon(Icons.cancel_outlined, size: 14, color: Colors.white),

          if (isPresent || isRegulizationRequested || !isPresent)
            const SizedBox(width: 4), // Add space if icon exists

          Text(
            statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: Error State Widget ---
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              _fetchErrorMessage ?? "An error occurred",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[400], // Lighter grey for message body
                height: 1.4, // Improve line spacing for readability
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeAndFetchData, // Retry full init
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    10,
                  ), // Consistent rounding
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper: Loading State Widget ---
  // --- Helper: Loading State Widget (Simplified) ---
  Widget _buildLoadingShimmer() {
    // Use ListView.builder for efficiency if list can be long,
    // or Column + List.generate if always short. ListView is fine.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10), // Reduced padding
      itemCount: 3, // Show 3 skeleton items (adjust as needed)
      itemBuilder: (context, index) {
        // Directly build the shimmer card, no separate group needed for this simple version
        return _buildShimmerCard();
      },
    );
  }

  // --- Helper: Shimmer Card Widget (Simplified) ---
  Widget _buildShimmerCard() {
    // Define placeholder color
    final Color placeholderColor =
        Colors.white.withValues(); // Subtle grey for dark theme
    final BorderRadius borderRadius = BorderRadius.circular(4);

    return Padding(
      // Use the same padding as real cards for consistency
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        // Use card theme or define style matching real cards
        elevation: 0, // Flatter look for skeleton
        color: Colors.white.withValues(), // Slightly different background
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          // Optional: remove border or make it subtler for skeleton
          // side: BorderSide(color: Colors.grey[850]!, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shimmer for Subject Name (Full Width)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  height: 20, // Adjust height
                  width: double.infinity, // Take full width
                  decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: borderRadius,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Shimmer for Subject Code (Shorter Width)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  height: 14, // Adjust height
                  width: 100, // Fixed shorter width
                  decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: borderRadius,
                  ),
                ),
              ),
              const SizedBox(height: 18), // More space before details
              // Shimmer for Detail Lines (Time, Teacher, Location)
              // Combine into one loop for simplicity
              for (int i = 0; i < 3; i++) ...[
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    height: 14, // Adjust height
                    // Vary widths slightly for realism
                    width: i == 0 ? 150 : (i == 1 ? 180 : 130),
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: borderRadius,
                    ),
                  ),
                ),
                // Add space only between lines
                if (i < 2) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper: Empty State Widget ---
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            'No lectures scheduled for today',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _fetchTimetableData(showLoading: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Check Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:smartroll/Screens/login_screen.dart';
import 'package:smartroll/Screens/manual_marking_dialouge.dart'; // Ensure this path is correct
import 'package:smartroll/utils/Constants.dart';
import 'package:smartroll/utils/auth_service.dart';
import 'package:smartroll/utils/device_id_service.dart';
import 'splash_screen.dart'; // Ensure this path is correct
import 'error_screen.dart'; // Ensure this path is correct

// --- Centralized Configuration ---
const String _backendBaseUrl = backendBaseUrl;

class AttendanceMarkingScreen extends StatefulWidget {
  const AttendanceMarkingScreen({super.key});

  @override
  State<AttendanceMarkingScreen> createState() =>
      _AttendanceMarkingScreenState();
}

class _AttendanceMarkingScreenState extends State<AttendanceMarkingScreen> {
  final Location _location = Location();
  final AuthService _authService = AuthService();
  final deviceIdService = DeviceIDService();
  final SecurityService _securityService = SecurityService();

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
  // ---------------------

  @override
  void initState() {
    super.initState();
    _initializeAndFetchData();
  }

  // --- Initialization and Data Fetching (Unchanged from previous safe version) ---
  Future<void> _initializeAndFetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTimetable = true;
      _fetchErrorMessage = null;
    });
    _accessToken = await secureStorage.read(key: 'accessToken');
    // _accessToken = _hardcodedAccessToken; // Using constant for example
    if (_accessToken == null || _accessToken!.isEmpty) {
      _handleCriticalError("Authentication token missing. Please login again.");
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
    if (showLoading && mounted) {
      setState(() {
        _isLoadingTimetable = true;
        _fetchErrorMessage = null;
      });
    }
    if (_accessToken == null) {
      if (mounted) _handleFetchError("Access token not available.");
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
        String errorMsg = 'Failed to load timetable (${response.statusCode})';
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
        _handleFetchError("Could not fetch timetable: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
      }
    }
  }
  // ---------------------------------------

  // --- Location Handling (Unchanged) ---
  // --- Updated Location Handling ---
  Future<LocationData?> _getCurrentLocation() async {
    // 1. Check Location Service (GPS) Status
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      // Request user to enable location services
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        // Service still not enabled, inform user and stop
        if (mounted) {
          _showSnackbar(
            'Please enable GPS/Location Services to mark attendance.',
            isError: true,
          );
        }
        return null;
      }
    }

    // 2. Check Location Permission Status
    PermissionStatus permission = await _location.hasPermission();

    if (permission == PermissionStatus.deniedForever) {
      // Permission permanently denied, guide user to settings
      if (mounted) {
        _showPermissionDialog(
          "Location Permission Required",
          "Location permission was permanently denied. To mark attendance, please enable it for SmartRoll in your phone's settings.",
          AppSettingsType.location, // Tries to open location settings directly
        );
      }
      return null; // Stop the process
    }

    if (permission == PermissionStatus.denied) {
      // Permission denied, request it once
      permission = await _location.requestPermission();

      if (permission == PermissionStatus.denied) {
        // User denied the permission again
        if (mounted) {
          _showPermissionDialog(
            "Location Permission Required",
            "SmartRoll needs location access to verify attendance. Please grant permission in the app settings.",
            AppSettingsType.settings, // Open general app settings as fallback
          );
        }
        return null; // Stop the process
      } else if (permission == PermissionStatus.deniedForever) {
        // User denied permanently after the request
        if (mounted) {
          _showPermissionDialog(
            "Location Permission Required",
            "Location permission was permanently denied. Please enable it for SmartRoll in your phone's settings.",
            AppSettingsType.location,
          );
        }
        return null; // Stop the process
      }
      // If permission is now granted, proceed (falls through to the next check)
    }

    // 3. If permission is granted (either initially or after request)
    if (permission == PermissionStatus.granted) {
      try {
        // Set desired accuracy (consider 'balanced' for potentially faster indoor results)
        await _location.changeSettings(accuracy: LocationAccuracy.high);
        // Attempt to get location with a timeout
        LocationData locationData = await _location.getLocation().timeout(
          const Duration(seconds: 10),
        );
        if (locationData.isMock == true) {
          // Check if isMock is explicitly true
          debugPrint("Mock location detected!");
          if (mounted) {
            _showSnackbar(
              "Mock location detected. Attendance marking disabled.",
              isError: true,
            );
          }
          return null; // Return null to prevent marking
        }
        return locationData;
      } catch (e) {
        // Handle errors during location fetching (e.g., timeout, platform exception)
        if (mounted) {
          _showSnackbar(
            'Could not get current location: ${e.toString()}',
            isError: true,
          );
        }
        return null;
      }
    } else {
      // Fallback case if permission status is somehow not granted after checks
      // (should ideally be caught by earlier checks)
      if (mounted) {
        _showSnackbar(
          'Location permission is required but was not granted.',
          isError: true,
        );
      }
      return null;
    }
  }

  // --- Helper Function for Permission Dialog ---
  void _showPermissionDialog(
    String title,
    String content,
    AppSettingsType settingsType,
  ) {
    // Check mounted again before showing dialog, as context might be invalid
    // if the user navigated away quickly after the await calls.
    if (!mounted) return;

    showDialog(
      context: context, // Use the widget's context
      barrierDismissible: false, // User must interact with the dialog
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
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

  // --- Attendance Marking Logic (Unchanged from previous safe version) ---
  Future<void> _handleMarkAttendance(dynamic lecture, {String? reason}) async {
    final String lectureSlug = lecture['slug'];
    if (_isMarkingLecture[lectureSlug] == true) return;

    final String initiator = reason == null ? 'auto' : 'manual';
    if (!mounted) return;

    bool devModeEnabledNow = false;
    try {
      // Assuming you have access to SecurityService instance (_securityService)
      devModeEnabledNow = await _securityService.isDeveloperModeEnabled();
    } catch (e) {
      debugPrint("Error re-checking dev mode: $e");
    }

    if (devModeEnabledNow) {
      debugPrint("Developer mode detected at time of marking. Aborting.");
      if (mounted) {
        // _showSnackbar(
        //   "Attendance marking disabled while Developer Options are active.",
        //   isError: true,
        // );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ErrorScreen(
                  message:
                      "Attendance marking disabled while Developer Options are active.",
                  // showRetryButton: false,
                ),
          ),
        );
      }
      // _resetMarkingState(lectureSlug); // Reset UI if needed
      return; // Stop the marking process
    }

    setState(() {
      _isMarkingLecture[lectureSlug] = true;
      _markingInitiator[lectureSlug] = initiator;
    });

    LocationData? locationData;
    if (reason == null) {
      locationData = await _getCurrentLocation();
      if (!mounted) {
        _resetMarkingState(lectureSlug);
        return;
      }
      if (locationData == null) {
        _resetMarkingState(lectureSlug);
        return;
      }
    }

    if (_accessToken == null) {
      _showSnackbar("Authentication error.", isError: true);
      _resetMarkingState(lectureSlug);
      return;
    }
    if (_deviceId == null) {
      _showSnackbar("Device ID error. Retrying...", isError: true);
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

    try {
      final String url =
          reason != null
              ? '$_backendBaseUrl/api/manage/session/mark_for_regulization/'
              : '$_backendBaseUrl/api/manage/session/mark_attendance_for_student/';
      final Map<String, dynamic> requestBody = {
        'lecture_slug': lectureSlug,
        'device_id': base64Encode(utf8.encode(_deviceId!)),
        if (reason != null) 'regulization_commet': reason,
        if (reason == null && locationData != null) ...{
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
        },
      };
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      if (!mounted) return;
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (responseData['data'] == true && responseData['code'] == 100) {
          _showSnackbar(
            reason == null ? 'Attendance marked!' : 'Manual request submitted!',
            isError: false,
          );
          await _fetchTimetableData(showLoading: false); // Refresh silently
        } else {
          throw Exception(
            responseData['message'] ??
                (reason == null ? 'Failed to mark' : 'Failed to submit'),
          );
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint("Received 401/403. Attempting token refresh...");
        // Attempt refresh using the service
        final refreshSuccess = await _authService.attemptTokenRefresh();

        if (refreshSuccess == RefreshStatus.success) {
          debugPrint("Refresh successful. Retrying original request...");
          // Get the NEW access token
          String? newAccessToken = await secureStorage.read(key: 'accessToken');
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            // Retry the original request with the new token
            final retryResponse = await http.post(
              Uri.parse(
                '$backendBaseUrl/api/manage/session/mark_attendance_for_student/',
              ),
              headers: {
                'Authorization': 'Bearer $newAccessToken', // Use NEW token
                'Content-Type': 'application/json',
              },
              body: jsonEncode(requestBody),
            );

            // Handle the retryResponse (check status code 200, etc.)
            if (retryResponse.statusCode == 200) {
              // Process successful retry...
              _showSnackbar('Attendance marked successfully!', isError: false);
              await _fetchTimetableData(showLoading: false); // Refresh UI
            } else {
              // Retry also failed
              throw Exception(
                'Failed to mark attendance after refresh (${retryResponse.statusCode})',
              );
            }
          } else {
            // Should not happen if refreshSuccess is true, but handle defensively
            throw Exception(
              'Refresh reported success but new token is missing.',
            );
          }
        } else {
          // Refresh failed, logout and navigate
          debugPrint("Refresh failed. Logging out.");
          await _authService.clearTokens(); // Clear tokens
          if (mounted) {
            // Ensure widget is still mounted before navigating
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => LoginScreen()),
              (route) => false,
            );
            // Show a message *after* navigation or on LoginScreen
            // _showSnackbar('Session expired. Please log in again.', isError: true);
          }
          return; // Stop further processing in this function
        }
      } else {
        String errorMessage = responseData['message'] ?? 'Server error';
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('Error: ${e.toString()}', isError: true);
    } finally {
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

    // --- DEBUGGING STEP (Optional): Replace with a simple dialog first ---
    // showDialog(
    //   context: context,
    //   builder: (context) => AlertDialog(
    //     title: Text("Debug Dialog"),
    //     content: Text("Lecture Slug: ${lecture['slug']}\nSubject: $subjectName"),
    //     actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("Close"))],
    //   )
    // );
    // If the above debug dialog shows without crashing, the issue is likely INSIDE ManualMarkingDialog.
    // If the debug dialog *still* crashes, the issue is likely with the context or the lecture object itself.
    // --- END DEBUGGING STEP ---

    // --- Original Dialog Call (assuming ManualMarkingDialog is safe) ---
    // Ensure ManualMarkingDialog widget exists and is correctly imported.
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

  // --- UI Helpers (Unchanged) ---
  void _handleLogout() async {
    await secureStorage.deleteAll();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SplashScreen()),
        (route) => false,
      );
    }
  }

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

  void _showSnackbar(String message, {bool isError = true}) {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: isError ? 4 : 3),
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
        title: const Text(
          'SMARTROLL',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        leading: IconButton(
          tooltip: "Refresh Schedule", // Add tooltip for accessibility
          icon: const Icon(Icons.refresh),
          // Use the same onPressed logic as before
          onPressed:
              _isLoadingTimetable || _isMarkingLecture.containsValue(true)
                  ? null
                  : () => _fetchTimetableData(showLoading: true),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout),
        ],
      ),
      body: _buildBodyWithDividers(), // Call the new body builder
    );
  }

  // --- Body Builder with Dividers and Styled Header ---
  Widget _buildBodyWithDividers() {
    if (_isLoadingTimetable) {
      // return const Center(
      //   // child: CircularProgressIndicator(color: Colors.blueAccent),
      // );
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
    final String? markingTime =
        attendanceData?['marking_time']; // Might be useful later

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
      // Show nothing if status is null or unexpected
      // Add padding to maintain card height consistency if needed
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
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeAndFetchData, // Retry full init
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper: Loading State Widget ---
  Widget _buildLoadingShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: 2, // Show 2 skeleton groups
      itemBuilder: (context, groupIndex) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch name shimmer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, child) {
                      return Container(
                        width: 200,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.grey[800]!,
                              Colors.grey[600]!,
                              Colors.grey[800]!,
                            ],
                            stops: [0.0, _shimmerController.value, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Lecture card shimmers
            ...List.generate(3, (index) => _buildShimmerCard()),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildShimmerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[850]!, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) {
                            return Container(
                              width: double.infinity,
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.grey[800]!,
                                    Colors.grey[600]!,
                                    Colors.grey[800]!,
                                  ],
                                  stops: [0.0, _shimmerController.value, 1.0],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) {
                            return Container(
                              width: 120,
                              height: 16,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.grey[800]!,
                                    Colors.grey[600]!,
                                    Colors.grey[800]!,
                                  ],
                                  stops: [0.0, _shimmerController.value, 1.0],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...List.generate(
                3,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        index == 0
                            ? Icons.access_time
                            : index == 1
                            ? Icons.person_outline
                            : Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return Container(
                            width: 150,
                            height: 16,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.grey[800]!,
                                  Colors.grey[600]!,
                                  Colors.grey[800]!,
                                ],
                                stops: [0.0, _shimmerController.value, 1.0],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

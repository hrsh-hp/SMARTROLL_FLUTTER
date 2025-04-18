import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:location/location.dart';

import 'package:smartroll/Screens/login_screen.dart';
import 'package:smartroll/Screens/dialogue_utils.dart'; // Ensure this path is correct
import 'package:smartroll/utils/mark_attendance_service.dart';
import 'error_screen.dart'; // Ensure this path is correct

import 'package:smartroll/utils/constants.dart';
import 'package:smartroll/utils/attendace_data_collector.dart';
import 'package:smartroll/utils/auth_service.dart';
import 'package:smartroll/utils/device_id_service.dart'; // Ensure this path is correct
import 'package:smartroll/utils/effects.dart';

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

  late final MarkAttendaceService _attendanceHandlerService;

  // --- State Variables (Original Names) ---
  bool _isLoadingTimetable = true;
  String? _fetchErrorMessage;
  List<dynamic> _timetableData = [];
  String? _deviceId;
  String? _accessToken;

  // State for button disabling and loading indicators per lecture
  final Map<String, bool> _isMarkingLecture = {};
  final Map<String, String> _markingInitiator = {};
  // ---------------------

  @override
  void initState() {
    super.initState();
    _attendanceHandlerService = MarkAttendaceService(
      securityService: _securityService,
      dataCollector: _dataCollector,
      authService: _authService,
      deviceIDService: deviceIdService,
    );
    _initializeAndFetchData();
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
    DialogUtils.showManualMarkingDialog(
      // Call the static method
      context: context,
      subjectName:
          lecture['subject']?['subject_map']?['subject_name'] ??
          'Unknown Subject',
      onSubmit: (String reason) {
        // Callback triggers the service call
        _attendanceHandlerService.handleAttendance(
          context: context,
          setState: setState,
          isMarkingLecture: _isMarkingLecture,
          markingInitiator: _markingInitiator,
          resetMarkingState: _resetMarkingState,
          lecture: lecture, // Pass the original lecture data
          currentAccessToken: _accessToken,
          currentDeviceId: _deviceId,
          showSnackbar: _showSnackbar,
          handleCriticalError: _handleCriticalError,
          fetchTimetableData: _fetchTimetableData,
          getAndStoreDeviceId: _getAndStoreDeviceId,
          loadAccessToken: _loadAccessToken,
          reason: reason, // Pass the reason collected from the sheet
        );
      },
    );
    // showDialog(
    //   context: context,
    //   barrierDismissible: false, // Good practice while submitting
    //   builder:
    //       (context) => ManualMarkingialog(
    //         subjectName: subjectName, // Pass the safely extracted name
    //         onSubmit: (reason) {
    //           // Navigator.of(context).pop(); // Close dialog
    //           // Call the original handler, passing the original lecture object
    //           _attendanceHandlerService.handleAttendance(
    //             context: context,
    //             setState: setState,
    //             isMarkingLecture: _isMarkingLecture,
    //             markingInitiator: _markingInitiator,
    //             resetMarkingState: _resetMarkingState,
    //             lecture: lecture, // Pass the original lecture data
    //             currentAccessToken: _accessToken,
    //             currentDeviceId: _deviceId,
    //             showSnackbar: _showSnackbar,
    //             showPermissionDialog: _showPermissionDialog,
    //             handleCriticalError: _handleCriticalError,
    //             fetchTimetableData: _fetchTimetableData,
    //             getAndStoreDeviceId: _getAndStoreDeviceId,
    //             loadAccessToken: _loadAccessToken,
    //             reason: reason, // Pass the reason collected from the sheet
    //           );
    //         },
    //       ),
    // ).catchError((error) {
    //   // Catch potential errors during dialog build/display
    //   debugPrint("Error showing dialog: $error");
    //   _showSnackbar("Could not open manual marking dialog.", isError: true);
    // });
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
      return const LoadingShimmer();
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
      color: Theme.of(context).colorScheme.primary,
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
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
                    : () {
                      _attendanceHandlerService.handleAttendance(
                        context: context,
                        setState: setState,
                        isMarkingLecture: _isMarkingLecture,
                        markingInitiator: _markingInitiator,
                        resetMarkingState: _resetMarkingState,
                        lecture: lecture,
                        currentAccessToken: _accessToken,
                        currentDeviceId: _deviceId,
                        showSnackbar: _showSnackbar,
                        handleCriticalError: _handleCriticalError,
                        fetchTimetableData: _fetchTimetableData,
                        getAndStoreDeviceId: _getAndStoreDeviceId,
                        loadAccessToken: _loadAccessToken,
                        reason: null, // Indicate 'auto' marking
                      );
                    },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              disabledBackgroundColor: Colors.grey.shade700,
              disabledForegroundColor: Colors.grey.shade400,
            ),
            child:
                isCurrentlyMarking && initiator == 'manual'
                    ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
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
                backgroundColor: Theme.of(context).colorScheme.primary,
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
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

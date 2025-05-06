import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'package:smartroll/Screens/dialogue_utils.dart'; // Ensure this path is correct
import 'package:smartroll/services/mark_attendance_service.dart';
import 'error_screen.dart'; // Ensure this path is correct

import 'package:smartroll/utils/constants.dart';
import 'package:smartroll/utils/attendace_data_collector.dart';
import 'package:smartroll/services/auth_service.dart';
import 'package:smartroll/services/device_id_service.dart'; // Ensure this path is correct
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final deviceIdService = DeviceIDService();
  final SecurityService _securityService = SecurityService();
  final AttendanceDataCollector _dataCollector = AttendanceDataCollector();

  late final MarkAttendaceService _attendanceHandlerService;
  final Set<String> _cancelledMarkingSlugs = {};

  bool _isLoadingTimetable = true;
  String? _fetchErrorMessage;
  // List<dynamic> _timetableData = [];
  String? _deviceId;
  String? _accessToken;

  // State for button disabling and loading indicators per lecture
  final Map<String, bool> _isMarkingLecture = {};
  final Map<String, String> _markingInitiator = {};
  List<Map<String, dynamic>> _groupedTimetableData = [];

  @override
  void initState() {
    super.initState();
    _attendanceHandlerService = MarkAttendaceService(
      securityService: _securityService,
      dataCollector: _dataCollector,
      authService: _authService,
      deviceIDService: deviceIdService,
    );
    WidgetsBinding.instance.addObserver(this); // Register observer
    _initializeAndFetchData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Unregister observer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    //debugPrint("AttendanceScreen Lifecycle State: $state");

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // App is going into the background or becoming inactive (e.g., phone call)
      // Check if any lecture is currently being marked
      _isMarkingLecture.forEach((lectureSlug, isMarking) {
        if (isMarking) {
          //debugPrint("App pausing/inactive during marking for lecture: $lectureSlug. Cancelling.");
          _cancelledMarkingSlugs.add(lectureSlug);
          // Immediately reset the UI state for this lecture
          _resetMarkingState(lectureSlug);
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      // App came back to the foreground
      if (_cancelledMarkingSlugs.isNotEmpty) {
        // Show snackbar for the first cancelled lecture (or a general message)
        _showSnackbar(
          "Attendance marking stopped. Please do not close or minimize the app while marking.",
          isError: true,
          duration: const Duration(
            seconds: 5,
          ), // Longer duration for visibility
        );
        // Clear the cancelled flags now that the message is shown
        _cancelledMarkingSlugs.clear();
      }
    }
  }

  Future<void> _loadAccessToken() async {
    // Use actual storage read
    _accessToken = await secureStorage.read(key: 'accessToken');
    //debugprint("Access token loaded: ${_accessToken != null}");
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
      //debugprint("Device ID: $_deviceId");
    } catch (e) {
      //debugprint("Error getting device ID: $e");
    }
  }

  // This function processes the raw API data into the grouped structure
  void _processAndGroupTimetableData(List<dynamic> rawData) {
    List<Map<String, dynamic>> groupedData = [];

    for (var streamGroup in rawData) {
      final String currentBranchName =
          streamGroup['stream']?['branch']?['branch_name'] ?? 'Unknown Branch';
      final List<dynamic> timetables =
          streamGroup['timetables'] as List<dynamic>? ?? [];
      List<dynamic> lecturesInBranch = [];

      for (var timetable in timetables) {
        if (timetable != null) {
          lecturesInBranch.addAll(
            timetable['lectures'] as List<dynamic>? ?? [],
          );
        }
      }

      // Sort lectures within the branch by start time
      lecturesInBranch.sort((a, b) {
        try {
          final timeA = DateFormat("HH:mm").parse(a['start_time']);
          final timeB = DateFormat("HH:mm").parse(b['start_time']);
          return timeA.compareTo(timeB);
        } catch (e) {
          return 0; 
        }
      });

      // Only add the branch group if it has lectures
      if (lecturesInBranch.isNotEmpty) {
        groupedData.add({
          'branchName': currentBranchName,
          'lectures': lecturesInBranch,
        });
      }
    }

    // --- Update the state variable ---
    if (mounted) {
      setState(() {
        _groupedTimetableData = groupedData;
        _fetchErrorMessage = null; // Clear previous errors if successful
      });
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
            _processAndGroupTimetableData(decodedBody['data']);
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

  // --- Manual Marking Dialog call---
  void _showManualMarkingDialog(dynamic lecture) {
    DialogUtils.showManualMarkingDialog(
      // Call the static method
      context: context,
      subjectName:
          "${lecture['subject']?['subject_map']?['subject_name']} (${lecture['type']})",
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
  }

  // // --- LOGOUT ---
  Future<void> _handleLogout() async {
    // --- Show Confirmation Dialog ---
    final bool? confirmLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must choose an action
      builder: (BuildContext dialogContext) {
        final theme = Theme.of(context); // Get theme for styling

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
            'Are you sure you want to log out and exit the app?',
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
    // --- End Confirmation Dialog ---

    // --- Process Confirmation ---
    // Check if the dialog returned true (meaning user confirmed)
    if (confirmLogout == true) {
      //debugPrint("User confirmed logout. Clearing data and exiting.");

      // 1. Clear Secure Storage (using your AuthService or directly)
      try {
        // Assuming AuthService has a clearTokens method that uses secureStorage
        await _authService.clearTokens();
        // OR if accessing directly:
        // await _storage.deleteAll();
        //debugPrint("Secure storage cleared.");
      } catch (e) {
        //debugPrint("Error clearing secure storage during logout: $e");
        // Decide if you still want to exit or show an error
      }

      // 2. Close the App
      // Use SystemNavigator.pop() to exit the application.
      // Note: This might be discouraged on iOS by Apple's guidelines for
      // normal app flows, but it's often acceptable for a logout/exit action.
      await SystemNavigator.pop();
    } else {
      //debugPrint("User cancelled logout.");
      // Do nothing if user cancelled
    }
  }

  void _handleFetchError(String message) {
    if (mounted) {
      setState(() {
        _fetchErrorMessage = message;
        _isLoadingTimetable = false;
        // _timetableData = [];
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

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _showSnackbar(
    String message, {
    bool isError = true,
    Color? backgroundColor,
    Duration? duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return null;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            backgroundColor ??
            (isError
                ? Colors.red.shade700
                : Colors.green), // Use a neutral color for progress
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(minutes: 5),
      ),
    );
    return controller;
  }

  String _formatTime(String timeString) {
    try {
      if (timeString.contains('.')) timeString = timeString.split('.').first;
      final parsedTime = DateFormat("HH:mm:ss").parse(timeString);
      return DateFormat("h:mm a").format(parsedTime);
    } catch (e) {
      //debugprint("Error formatting time '$timeString': $e");
      return timeString;
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 3,
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
      return const LoadingShimmer(); // Or your preferred loading indicator
    }
    if (_fetchErrorMessage != null) {
      return _buildErrorState();
    }
    if (_groupedTimetableData.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _fetchTimetableData(showLoading: false),
      color: Theme.of(context).colorScheme.primary, // Adjust as needed
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: ListView.builder(
        // Let the outer card's margin handle spacing, adjust list padding if needed
        padding: const EdgeInsets.symmetric(
          vertical: 8.0,
        ), // Minimal vertical padding for the list itself
        itemCount: _groupedTimetableData.length,
        itemBuilder: (context, index) {
          // Get the data for the current branch group
          final branchGroup = _groupedTimetableData[index];
          final String branchName = branchGroup['branchName'];
          final List<dynamic> lectures = branchGroup['lectures'];

          // --- Return the Outer Card for the Branch Group ---
          return Card(
            margin:
                Theme.of(context).cardTheme.margin ?? // Use theme margin
                const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 12.0,
                ), // Fallback
            clipBehavior: Clip.antiAlias, // Good practice for rounded corners
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Branch Name Header ---
                Padding(
                  padding: const EdgeInsets.only(
                    top: 16.0, // Space above branch name inside the card
                    left: 16.0, // Indent branch name
                    right: 16.0,
                    bottom: 8.0, // Space below branch name before lecture cards
                  ),
                  child: Text(
                    branchName,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600, // Make it stand out
                      color:
                          Theme.of(context).colorScheme.onSurface.withValues(),
                      letterSpacing: 0.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),

                // --- List of Lecture Cards (Inner Cards) ---
                Column(
                  children:
                      lectures.map((lecture) {
                        // Build the inner lecture card
                        final lectureCard = _buildLectureCard(lecture);

                        // Add padding around the *inner* lecture card for spacing
                        // within the outer card. Reduce horizontal padding slightly
                        // compared to the outer card's margin.
                        return Padding(
                          padding: const EdgeInsets.only(
                            left: 8.0, // Inner horizontal padding
                            right: 8.0,
                            bottom: 10.0, // Space between lecture cards
                          ),
                          child: lectureCard,
                        );
                      }).toList(),
                ),
                // Add a little padding at the bottom of the outer card
                const SizedBox(height: 6.0),
              ],
            ),
          );
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
    final bool isManuallyMarked = attendanceData?['manual'] ?? false;
    final bool isRegulizationRequested =
        attendanceData?['regulization_request'] ?? false;

    final String? activeStatus =
        sessionData?['active']?.toString().toLowerCase(); // Get active status

    final String subjectName =
        lecture['subject']?['subject_map']?['subject_name'] ??
        'Unknown Subject';
    final String subjectCode =
        lecture['subject']?['subject_map']?['subject_code'] ?? '';
    final String teacherName = lecture['teacher'] ?? 'N/A';
    final String classroom = lecture['classroom']?['class_name'] ?? 'N/A';
    final String lectureType = lecture['type']?.toString().toUpperCase() ?? '';
    final String semester =
        lecture['subject']?['semester']?['no'].toString() ?? '';
    final String division =
        lecture['batches']?[0]['division']?['division_name'].toString() ?? '';
    final String batch = lecture['batches']?[0]['batch_name']?.toString() ?? '';
    String semDivBatchDisplay = semester;
    if (lectureType == 'THEORY') {
      if (division.isNotEmpty) {
        semDivBatchDisplay += '-$division';
      }
    } else {
      if (batch.isNotEmpty) {
        semDivBatchDisplay += '-$batch';
      } else {
        semDivBatchDisplay += '-$division';
      }
    }

    String? sessionDate = sessionData?['day']?.toString();
    if (sessionDate != null) {
      try {
        final DateTime parsedDate = DateTime.parse(sessionDate);
        // Format date as 'MMM dd, yyyy' (Target format)
        sessionDate = DateFormat('MMM dd, yyyy').format(parsedDate);
      } catch (e) {
        //debugprint("Error parsing session date: $sessionDate: $e");
        sessionDate =
            sessionData?['day']?.toString(); // Fallback to original string
      }
    }
    Color typeChipColor = Colors.blueAccent.shade200;
    if (lectureType == 'LAB') typeChipColor = const Color(0xFFAB47BC);
    if (lectureType == 'TUTORIAL') typeChipColor = Colors.orange.shade700;

    // Button states (remain the same)
    final bool isCurrentlyMarking = _isMarkingLecture[lectureSlug] ?? false;
    final String? initiator = _markingInitiator[lectureSlug];

    // Return the Card structure from your original code
    return Card(
      elevation: 3,
      // margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.grey.shade100, // Subtle border color
          width: 1,
        ), // Subtle border
      ),
      color: Theme.of(context).colorScheme.secondaryContainer,
      shadowColor: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Top Row: Subject, Code & Status Chip ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Left: Subject & Code ---
                Expanded(
                  // Allow text wrapping
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        softWrap: true,
                        // maxLines: 3,
                        // overflow: TextOverflow.ellipsis,
                      ),
                      if (subjectCode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '($subjectCode)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 2), // Space before chip
                // --- Right: Status Chip ---
                // (Keep your existing logic for showing the chip)
                if (isMarked || isManuallyMarked || isRegulizationRequested)
                  _buildAttendanceStatusChip(
                    isMarked || isManuallyMarked,
                    isRegulizationRequested,
                  ),
              ],
            ),
            const SizedBox(height: 8), // Space after top row
            // --- Type Chip ---
            if (lectureType.isNotEmpty) ...[
              Align(
                // Align it left if needed
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, // Adjust padding
                    vertical: 4, // Adjust padding
                  ),
                  decoration: BoxDecoration(
                    // Use specific color for 'Theory' from target (Orange-ish)
                    color:
                        lectureType == 'THEORY'
                            ? Colors
                                .orange
                                .shade700 // Target orange
                            : typeChipColor, // Keep logic for others
                    borderRadius: BorderRadius.circular(6), // Target radius
                  ),
                  child: Text(
                    lectureType, // Capitalize first letter? target shows "Theory"
                    style: TextStyle(
                      color: Colors.white, // Text color on chip
                      fontSize: 11, // Adjust size
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12), // Space after type chip
            ],

            _buildDetailTextRow(label: "Teacher: ", value: teacherName),
            const SizedBox(height: 10),
            _buildDetailTextRow(label: "Sem: ", value: semDivBatchDisplay),
            const SizedBox(height: 10),

            // --- Classroom Info ---
            _buildDetailIconRow(
              icon: Icons.location_city_outlined,
              value: classroom,
            ),
            const SizedBox(height: 8),

            // --- Time Info ---
            _buildDetailIconRow(
              icon: Icons.access_time_outlined,
              // Use updated _formatTime for HH:mm:ss
              value:
                  '${_formatTime(lecture['start_time'])} • ${_formatTime(lecture['end_time'])}',
            ), // Use bullet like target
            const SizedBox(height: 8),

            // --- Date Info ---
            _buildDetailIconRow(
              icon: Icons.calendar_today_outlined,
              // Use 'MMM dd, yyyy' format
              value: sessionDate ?? 'N/A',
            ), // sessionDate needs reformatting
            // --- Action Buttons (Keep existing logic) ---
            if (!isMarked && !isManuallyMarked) ...[
              const SizedBox(height: 16),
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
    );
  }

  Widget _buildDetailTextRow({required String label, required String value}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          // Default style for the row
          fontSize: 14,
          color:
              Colors.grey[700], // Use a suitable color from theme or hardcode
        ),
        children: <TextSpan>[
          TextSpan(
            text: label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
          ), // Label slightly bolder
          TextSpan(
            text: value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      maxLines: 2, // Allow wrapping
      overflow: TextOverflow.ellipsis,
    );
  }

  // Helper for Icon rows like Classroom, Time, Date
  Widget _buildDetailIconRow({required IconData icon, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.grey[600], size: 18), // Adjust size/color
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              // color: Colors.grey[700], // Use a suitable color
            ),
            maxLines: 1, // <<< CRUCIAL: Prevent wrapping
            overflow: TextOverflow.ellipsis, // <<< CRUCIAL: Handle overflow
          ),
        ),
      ],
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              disabledBackgroundColor: Colors.blueAccent.shade100,
              disabledForegroundColor: Colors.grey.shade400,
            ),
            child:
                isCurrentlyMarking && initiator == 'auto'
                    ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    )
                    : Text(
                      'Mark Attendance',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
          const SizedBox(height: 8.0),
          // Manual Marking Button
          ElevatedButton(
            onPressed:
                isMarked || isCurrentlyMarking || isRegulizationRequested
                    ? null
                    : () => _showManualMarkingDialog(lecture),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onPrimary,
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              disabledBackgroundColor: Colors.grey.shade300,
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
                          Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    )
                    : Text(
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
      chipColor = Color(0xFF4CB151); // Consistent green
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
        borderRadius: BorderRadius.circular(8), // Adjusted radius slightly
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
              color: Theme.of(context).colorScheme.onPrimary,
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
    final Color errorColor = Theme.of(context).colorScheme.error;
    final Color primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final Color secondaryTextColor = primaryTextColor.withAlpha(
      (0.5 * 255).toInt(),
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: errorColor.withValues(),
            ),
            const SizedBox(height: 24),
            Text(
              'Oops!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: primaryTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _fetchErrorMessage ??
                  "Something went wrong. Please try again.", // Default message
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: secondaryTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _initializeAndFetchData, // Retry full init
              icon: const Icon(Icons.refresh_rounded, size: 20), // Refined icon
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper: Empty State Widget (Modernized) ---
  Widget _buildEmptyState() {
    // Use theme colors
    final Color primaryTextColor = Theme.of(context).colorScheme.onSurface;
    // Use a neutral theme color for the icon, e.g., secondary or a grey derived from surface
    final Color iconColor = Theme.of(context).colorScheme.secondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined, size: 56, color: iconColor),
            const SizedBox(height: 24),

            Text(
              'No Ongoing Sessions currently.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: primaryTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => _fetchTimetableData(showLoading: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Check Again'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withValues(),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), //  rounding
                ),
                textStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

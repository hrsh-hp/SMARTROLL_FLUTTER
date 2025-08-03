import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:smartroll/Common/Screens/dialogue_utils.dart';
import 'package:smartroll/Common/Screens/error_screen.dart';
import 'package:smartroll/Common/utils/constants.dart';
import 'package:smartroll/Common/utils/effects.dart';
import 'package:smartroll/Teacher/Screens/live_session_screen.dart';
import 'package:smartroll/Teacher/services/session_service.dart';
import 'package:smartroll/Teacher/utils/teacher_data_provider.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final ScrollController _dateScrollController = ScrollController();

  bool _isLoading = true;
  bool _isFetching = false; // To prevent concurrent fetches
  String? _errorMessage;
  Map<String, List<Map<String, dynamic>>> _groupedLectures = {};
  DateTime _selectedDate = DateTime.now();
  List<DateTime> _monthDays = [];
  final Map<String, bool> _isExpanded = {};
  List<Map<String, dynamic>> _allClassrooms = [];

  final SessionService _sessionService = SessionService.instance;

  @override
  void initState() {
    super.initState();
    _generateMonthDays();
    _selectedDate = DateTime.now(); // Set today as the initial date
    _fetchInitialData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedDate();
    });
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Fetch classrooms first so the dropdowns have data
      await _fetchClassrooms();
      await _fetchTimetableForDay(DateTime.now());
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchClassrooms() async {
    try {
      final classrooms = await TeacherDataProvider.getClassrooms();
      if (mounted) {
        setState(() {
          _allClassrooms = classrooms;
        });
      }
    } catch (e) {
      // Handle error if classrooms fail to load, maybe show a snackbar
      print("Failed to fetch classrooms: $e");
    }
  }

  @override
  void dispose() {
    _dateScrollController.dispose();
    super.dispose();
  }

  void _generateMonthDays() {
    _monthDays = [];
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    for (
      int i = 0;
      i <= lastDayOfMonth.difference(firstDayOfMonth).inDays;
      i++
    ) {
      _monthDays.add(firstDayOfMonth.add(Duration(days: i)));
    }
  }

  void _scrollToSelectedDate() {
    final selectedDateIndex = _monthDays.indexWhere(
      (day) =>
          day.day == _selectedDate.day &&
          day.month == _selectedDate.month &&
          day.year == _selectedDate.year,
    );

    if (selectedDateIndex != -1) {
      final scrollOffset = selectedDateIndex * 72.0; // 64 (width) + 8 (margin)
      _dateScrollController.animateTo(
        scrollOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _fetchTimetableForDay(DateTime date) async {
    if (_isFetching) return;

    setState(() {
      _isFetching = true;
      _isLoading = true;
      _errorMessage = null;
      _selectedDate = date;
      _groupedLectures = {};
    });

    final bool connected = await NetwrokUtils.isConnected();
    if (!mounted) return;
    if (!connected) {
      setState(() {
        _errorMessage = "No internet connection. Please try again.";
        _isLoading = false;
        _isFetching = false;
      });
      return;
    }

    final String? token = await secureStorage.read(key: 'accessToken');
    if (token == null) {
      _handleCriticalError("Authentication failed. Please log in again.");
      return;
    }

    final day = DateFormat('EEEE').format(date).toLowerCase();
    final url = Uri.parse(
      '$backendBaseUrl/api/manage/get_timetable_for_teacher/$day',
    );

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);
        if (decodedBody['error'] == false && decodedBody['data'] is List) {
          _processAndSetLectures(decodedBody['data']);
        } else {
          setState(() {
            _errorMessage =
                decodedBody['message'] ?? 'Failed to load timetable.';
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleCriticalError('Your session has expired. Please log in again.');
      } else {
        setState(() {
          _errorMessage = 'Server error. Please try again later.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetching = false;
        });
      }
    }
  }

  void _processAndSetLectures(List<dynamic> data) {
    List<Map<String, dynamic>> processedLectures = [];
    for (var branch in data) {
      for (var stream in branch['streams']) {
        for (var semester in stream['semesters']) {
          for (var division in semester['divisions']) {
            final timetable = division['timetable'];
            if (timetable != null && timetable['schedule'] != null) {
              for (var lecture in timetable['schedule']['lectures']) {
                processedLectures.add({
                  ...lecture,
                  'branch_name': branch['branch_name'],
                  'stream_title': stream['title'],
                  'semester_no': semester['no'],
                  'division_name': division['division_name'],
                });
              }
            }
          }
        }
      }
    }

    Map<String, List<Map<String, dynamic>>> tempGroupedLectures = {};
    for (var lecture in processedLectures) {
      final branchName = lecture['branch_name'];
      tempGroupedLectures.putIfAbsent(branchName, () => []).add(lecture);
    }

    tempGroupedLectures.forEach((branch, lectures) {
      lectures.sort((a, b) => a['start_time'].compareTo(b['start_time']));
    });

    setState(() {
      _groupedLectures = tempGroupedLectures;
      for (var branch in _groupedLectures.keys) {
        _isExpanded.putIfAbsent(branch, () => true);
      }
    });
  }

  void _handleCriticalError(String message) {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => ErrorScreen(message: message)),
        (route) => false,
      );
    }
  }

  // Replace the existing _handleClassroomChange function with this one.

  Future<void> _handleClassroomChange(
    String? newClassroomSlug,
    Map<String, dynamic> lecture,
  ) async {
    if (newClassroomSlug == null) return;

    final String? token = await secureStorage.read(key: 'accessToken');
    if (token == null) {
      _handleCriticalError("Authentication failed. Please log in again.");
      return;
    }

    final lectureSlug = lecture['slug'];
    if (lectureSlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Missing lecture identifier.')),
      );
      return;
    }

    // *** CORRECTED PART: Build a GET request with query parameters ***
    final url = Uri.parse(
      '$backendBaseUrl/api/manage/session/get_classroom_allocations',
    ).replace(
      queryParameters: {
        'lecture_slug': lectureSlug,
        'classroom_slug': newClassroomSlug,
      },
    );

    try {
      // *** CORRECTED PART: Use http.get instead of http.post ***
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept':
              'application/json', // Good practice to specify expected response type
        },
      );

      if (!mounted) return;

      // The rest of the logic remains the same, as it correctly handles the response
      final decodedBody = jsonDecode(response.body);

      if (response.statusCode == 200 && decodedBody['error'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Classroom updated successfully.')),
        );
        // Refresh data to show the change from the source of truth
        // await _fetchTimetableForDay(_selectedDate);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decodedBody['message'] ?? 'Failed to update classroom.',
            ),
          ),
        );
        // Rebuild to revert optimistic UI change in dropdown
        setState(() {});
      }
    } catch (e) {
      // This catch block will now correctly handle the FormatException if it still occurs
      print("Error occurred while updating classroom: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An unexpected error occurred.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        title: SizedBox(
          width: MediaQuery.of(context).size.width * 0.4,
          child: Image.asset('assets/LOGO.webp', fit: BoxFit.contain),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              DialogUtils.showLogoutConfirmationDialog(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(child: Center(child: _buildBody())),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return AbsorbPointer(
      absorbing: _isFetching,
      child: Opacity(
        opacity: _isFetching ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          child: SizedBox(
            height: 72,
            child: ListView.builder(
              controller: _dateScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: _monthDays.length,
              itemBuilder: (context, index) {
                final day = _monthDays[index];
                final isSelected =
                    DateFormat('yyyy-MM-dd').format(day) ==
                    DateFormat('yyyy-MM-dd').format(_selectedDate);
                return GestureDetector(
                  onTap: () => _fetchTimetableForDay(day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 64,
                    margin: EdgeInsets.only(
                      left: index == 0 ? 16.0 : 8.0,
                      right: index == _monthDays.length - 1 ? 16.0 : 8.0,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(day).toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                isSelected
                                    ? Colors.white.withOpacity(0.8)
                                    : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d').format(day),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM').format(day).toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                isSelected
                                    ? Colors.white.withOpacity(0.8)
                                    : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingShimmer();
    }
    if (_errorMessage != null) {
      return _buildInfoState(
        icon: Icons.cloud_off_rounded,
        title: 'Something Went Wrong',
        message: _errorMessage!,
        isError: true,
      );
    }
    if (_groupedLectures.isEmpty) {
      return _buildInfoState(
        icon: Icons.event_note_outlined,
        title: 'No Lectures Today',
        message:
            'You have no classes scheduled for the selected day. Enjoy your break!',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _fetchTimetableForDay(_selectedDate),
      child: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: _groupedLectures.keys.length,
          itemBuilder: (context, index) {
            final branchName = _groupedLectures.keys.elementAt(index);
            final lectures = _groupedLectures[branchName]!;
            return _buildBranchCard(branchName, lectures);
          },
        ),
      ),
    );
  }

  Widget _buildInfoState({
    required IconData icon,
    required String title,
    required String message,
    bool isError = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: isError ? colorScheme.error : colorScheme.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            if (isError)
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () => _fetchTimetableForDay(_selectedDate),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(color: colorScheme.error.withOpacity(0.5)),
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

  Widget _buildBranchCard(
    String branchName,
    List<Map<String, dynamic>> lectures,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 4,
      color: Colors.grey.shade50,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(branchName),
        initiallyExpanded: _isExpanded[branchName] ?? true,
        onExpansionChanged: (isExpanded) {
          setState(() {
            _isExpanded[branchName] = isExpanded;
          });
        },
        title: Text(
          branchName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black,
          ),
        ),
        children:
            lectures.map((lecture) => _buildLectureCard(lecture)).toList(),
      ),
    );
  }

  Widget _buildLectureCard(Map<String, dynamic> lecture) {
    final subject = lecture['subject']['subject_map'];
    final session = lecture['session'];
    final classroom = lecture['classroom'];

    String semDivBatchDisplay = "${lecture['semester_no']}";
    if (lecture['type'].toString().toUpperCase() == 'THEORY') {
      semDivBatchDisplay += '-${lecture['division_name']}';
    } else {
      if (lecture['batches'] != null && lecture['batches'].isNotEmpty) {
        semDivBatchDisplay += '-${lecture['batches'][0]['batch_name']}';
      } else {
        semDivBatchDisplay += '-${lecture['division_name']}';
      }
    }

    final sessionStatus = session['active'];
    String buttonText;
    VoidCallback? onPressed;
    Color buttonColor = Theme.of(context).primaryColor;

    switch (sessionStatus) {
      case 'pre':
        buttonText = 'Start Session';
        onPressed = () => _handleStartSession(context, lecture);
        break;
      case 'ongoing':
        buttonText = 'Join Session';
        buttonColor = Colors.blue.shade800;
        onPressed = () => _handleStartSession(context, lecture);
        break;
      case 'post':
      default:
        buttonText = 'Session Ended';
        buttonColor = Colors.grey;
        onPressed = null; // Disabled
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    subject['subject_name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(session['active']),
              ],
            ),
            const SizedBox(height: 4),
            _buildTypeChip(lecture['type']),
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.school_outlined,
              'Semester:',
              semDivBatchDisplay,
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.schedule_outlined,
              'Time:',
              '${_formatTime(lecture['start_time'])} - ${_formatTime(lecture['end_time'])}',
            ),
            const SizedBox(height: 8),
            // *** CORRECTED WIDGET INTEGRATION ***
            ClassroomDropdown(
              key: ValueKey(
                lecture['slug'],
              ), // Add a key for proper state management
              classrooms: _allClassrooms,
              initialClassroom: classroom,
              onChanged: (newClassroomSlug) {
                _handleClassroomChange(newClassroomSlug, lecture);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: buttonColor,
                disabledBackgroundColor: Colors.grey.shade400,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  void _handleStartSession(
    BuildContext context,
    Map<String, dynamic> lecture,
  ) async {
    final classroomSlug = lecture['classroom']?['slug'];
    if (classroomSlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a classroom first.')),
      );
      return;
    }

    // Show a loading dialog for better UX
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final sessionData = await _sessionService.startSession(
        lectureSlug: lecture['slug'],
        classroomSlug: classroomSlug,
      );

      Navigator.of(context).pop(); // Dismiss loading dialog

      // Navigate to the live screen and wait for it to be popped
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LiveSessionScreen(sessionData: sessionData),
        ),
      );

      // After returning from LiveSessionScreen, refresh the dashboard
      _fetchTimetableForDay(_selectedDate);
    } catch (e) {
      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String text = status.toUpperCase();
    switch (status.toLowerCase()) {
      case 'ongoing':
        color = Colors.green;
        text = 'Active';
        break;
      case 'pre':
        color = Colors.blue;
        text = 'Upcoming';
        break;
      case 'post':
        color = Colors.grey;
        text = 'Finished';
        break;
      default:
        color = Colors.orange;
    }
    return Chip(
      label: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }

  Widget _buildTypeChip(String type) {
    Color color;
    switch (type.toLowerCase()) {
      case 'lab':
        color = Colors.purple.shade300;
        break;
      case 'tutorial':
        color = Colors.orange.shade400;
        break;
      default:
        color = Colors.orange.shade400;
    }
    return Chip(
      label: Text(
        type.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatTime(String timeString) {
    try {
      final parsedTime = DateFormat("HH:mm:ss").parse(timeString);
      return DateFormat("h:mm a").format(parsedTime);
    } catch (e) {
      return timeString;
    }
  }
}

// =========================================================================
// === REVISED AND CORRECTED CLASSROOM DROPDOWN WIDGET =====================
// =========================================================================

class ClassroomDropdown extends StatefulWidget {
  final List<Map<String, dynamic>> classrooms;
  final Map<String, dynamic>? initialClassroom;
  final ValueChanged<String?>? onChanged;

  const ClassroomDropdown({
    super.key,
    required this.classrooms,
    this.initialClassroom,
    this.onChanged,
  });

  @override
  State<ClassroomDropdown> createState() => _ClassroomDropdownState();
}

class _ClassroomDropdownState extends State<ClassroomDropdown> {
  String? _selectedClassroomSlug;
  List<DropdownMenuItem<String>> _items = [];

  @override
  void initState() {
    super.initState();
    // Use the slug from the initial classroom data to set the initial state
    _selectedClassroomSlug = widget.initialClassroom?['slug'];
    _buildDropdownItems();
  }

  @override
  void didUpdateWidget(covariant ClassroomDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild items if the classroom list or the initial classroom changes
    // This is important for when the parent widget refreshes the data
    if (widget.classrooms != oldWidget.classrooms ||
        widget.initialClassroom != oldWidget.initialClassroom) {
      setState(() {
        _selectedClassroomSlug = widget.initialClassroom?['slug'];
        _buildDropdownItems();
      });
    }
  }

  void _buildDropdownItems() {
    final seenSlugs = <String>{};
    // Filter out any classrooms that don't have a valid slug
    final validClassrooms =
        widget.classrooms.where((c) {
          final slug = c['slug'];
          if (slug != null && slug is String && slug.isNotEmpty) {
            // Use a Set to ensure each classroom slug appears only once
            return seenSlugs.add(slug);
          }
          return false;
        }).toList();

    // Create DropdownMenuItem from the valid list
    _items =
        validClassrooms.map((Map<String, dynamic> classroom) {
          return DropdownMenuItem<String>(
            value: classroom['slug'],
            child: Text(
              classroom['class_name'] ?? 'Unnamed Classroom',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList();

    // Defensive check: If the initial classroom is not in our main list,
    // add it temporarily so it can be displayed correctly.
    if (widget.initialClassroom != null &&
        !_items.any((item) => item.value == widget.initialClassroom!['slug'])) {
      _items.insert(
        0,
        DropdownMenuItem<String>(
          value: widget.initialClassroom!['slug'],
          child: Text(
            widget.initialClassroom!['class_name'] ?? 'Unnamed Classroom',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure the display value is actually in the list of items to prevent errors
    String? displayValue = _selectedClassroomSlug;
    if (displayValue != null &&
        !_items.any((item) => item.value == displayValue)) {
      displayValue = null; // Set to null if not found, showing the hint text
    }

    return Row(
      children: [
        Icon(Icons.people_outline, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 8),
        Text('Classroom:', style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: displayValue,
                hint: const Text("Select", style: TextStyle(fontSize: 14)),
                isExpanded: true,
                isDense: true,
                items: _items,
                menuMaxHeight: 300,
                onChanged: (newValue) {
                  // When a new value is selected, update the state
                  setState(() {
                    _selectedClassroomSlug = newValue;
                  });
                  // And trigger the callback to notify the parent widget
                  if (widget.onChanged != null) {
                    widget.onChanged!(newValue);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

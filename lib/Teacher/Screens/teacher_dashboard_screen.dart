// lib/Teacher/Screens/teacher_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:smartroll/Common/Screens/dialogue_utils.dart';
import 'package:smartroll/Common/Screens/error_screen.dart';
import 'package:smartroll/Common/services/auth_service.dart';
import 'package:smartroll/Common/utils/constants.dart';
import 'package:smartroll/Common/utils/effects.dart';
import 'package:smartroll/Common/Screens/login_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final AuthService _authService = AuthService();
  final ScrollController _dateScrollController = ScrollController();

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, List<Map<String, dynamic>>> _groupedLectures = {};
  DateTime _selectedDate = DateTime.now();
  List<DateTime> _monthDays = [];
  String? _selectedClassroom;
  final Map<String, bool> _isExpanded = {};

  @override
  void initState() {
    super.initState();
    _generateMonthDays();
    _fetchTimetableForDay(_selectedDate);

    // Scroll to the selected date after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedDate();
    });
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
      final scrollOffset = selectedDateIndex * 80.0;
      _dateScrollController.animateTo(
        scrollOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _fetchTimetableForDay(DateTime date) async {
    setState(() {
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
      if (tempGroupedLectures.containsKey(branchName)) {
        tempGroupedLectures[branchName]!.add(lecture);
      } else {
        tempGroupedLectures[branchName] = [lecture];
      }
    }

    tempGroupedLectures.forEach((branch, lectures) {
      lectures.sort((a, b) {
        return a['start_time'].compareTo(b['start_time']);
      });
    });

    setState(() {
      _groupedLectures = tempGroupedLectures;
      _groupedLectures.keys.forEach((branch) {
        _isExpanded.putIfAbsent(branch, () => true);
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        title: const Text('My Schedule'),
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
        children: [_buildDateSelector(), Expanded(child: _buildBody())],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              DateFormat('MMMM yyyy').format(_selectedDate),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
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
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('d').format(day),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _groupedLectures.keys.length,
        itemBuilder: (context, index) {
          final branchName = _groupedLectures.keys.elementAt(index);
          final lectures = _groupedLectures[branchName]!;
          return _buildBranchCard(branchName, lectures);
        },
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
    final isActionable = sessionStatus == 'ongoing' || sessionStatus == 'pre';
    final buttonText =
        sessionStatus == 'ongoing' ? 'Join Session' : 'Start Session';

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      padding: const EdgeInsets.all(16.0),
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
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusChip(session['active']),
            ],
          ),
          const SizedBox(height: 4),
          _buildTypeChip(lecture['type']),
          const SizedBox(height: 16),
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
          _buildClassroomDropdown(classroom['class_name']),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed:
                isActionable
                    ? () {
                      // TODO: Implement Join/Start Session
                    }
                    : null,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Theme.of(context).primaryColor,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  Widget _buildClassroomDropdown(String currentClassroom) {
    // For now, the list only contains the current classroom.
    final List<String> classrooms = [currentClassroom];
    _selectedClassroom ??= currentClassroom;

    return Row(
      children: [
        Icon(Icons.people_outline, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 8),
        Text('Classroom:', style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(width: 4),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedClassroom,
              isExpanded: true,
              items:
                  classrooms.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedClassroom = newValue;
                });
              },
            ),
          ),
        ),
      ],
    );
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

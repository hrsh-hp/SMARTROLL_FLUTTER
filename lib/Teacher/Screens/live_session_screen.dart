// lib/Teacher/Screens/live_session_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smartroll/Common/utils/effects.dart';
import 'package:smartroll/Teacher/services/session_service.dart';
import 'package:smartroll/Teacher/services/socket_service.dart';
import 'package:smartroll/Common/utils/constants.dart';

class LiveSessionScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  const LiveSessionScreen({super.key, required this.sessionData});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen>
    with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService.instance;
  final SocketService _socketService = SocketService.instance;

  late TabController _tabController;
  List<Map<String, dynamic>> _defaultStudents = [];
  List<Map<String, dynamic>> _manualRequests = [];
  int _activeStudentCount = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String? _authToken; // Store the auth token for reuse

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(
      () => setState(() {}),
    ); // To rebuild FAB on tab change
    _initializeSession();
  }

  void _initializeSession() async {
    _authToken = await secureStorage.read(key: 'accessToken');
    final String sessionId = widget.sessionData['session_id'];

    if (_authToken == null) {
      // Handle error
      return;
    }

    _sessionService.startRealAudioStream(
      onAudioChunk: (wavBlob) {
        _socketService.sendAudioChunk(
          sessionId: sessionId,
          authToken: _authToken!,
          wavBlob: wavBlob,
        );
      },
    );

    _socketService.connectAndListen(
      sessionId: sessionId,
      authToken: _authToken!,
    );

    Timer(const Duration(seconds: 10), () {
      if (_isLoading && mounted) setState(() => _isLoading = false);
    });

    _subscriptions.add(
      _socketService.defaultStudentsStream.listen(_onDefaultStudentReceived),
    );
    _subscriptions.add(
      _socketService.manualRequestsStream.listen(_onManualRequestReceived),
    );
    _subscriptions.add(
      _socketService.activeStudentCountStream.listen(
        (count) => setState(() => _activeStudentCount = count),
      ),
    );
    _subscriptions.add(
      _socketService.sessionEndedStream.listen((_) => _onSessionEnded()),
    );
    _subscriptions.add(
      _socketService.errorStream.listen(
        (error) => setState(() {
          _isLoading = false;
          _errorMessage = error;
        }),
      ),
    );
  }

  // --- Data Handling Logic ---
  void _onDefaultStudentReceived(Map<String, dynamic> student) {
    if (!mounted) return;

    final double ncc = (student['ncc'] as num?)?.toDouble() ?? 0.0;
    final double magnitude = (student['magnitude'] as num?)?.toDouble() ?? 0.0;
    student['isSuspicious'] = (ncc < 0.5 || magnitude < 0.02);

    setState(() {
      _isLoading = false;
      _errorMessage = null;
      final index = _defaultStudents.indexWhere(
        (s) => s['slug'] == student['slug'],
      );
      if (index != -1) {
        _defaultStudents[index] = student;
      } else {
        _defaultStudents.add(student);
      }
      // Ensure student is removed from manual list if they were just approved
      _manualRequests.removeWhere((r) => r['slug'] == student['slug']);
      _sortDefaultStudents();
      _activeStudentCount = _defaultStudents.length;
    });
  }

  void _sortDefaultStudents() {
    _defaultStudents.sort((a, b) {
      final bool aIsSuspicious = a['isSuspicious'] ?? false;
      final bool bIsSuspicious = b['isSuspicious'] ?? false;

      if (aIsSuspicious && !bIsSuspicious) {
        return -1; // a comes first
      } else if (!aIsSuspicious && bIsSuspicious) {
        return 1; // b comes first
      } else {
        // Optional: sort by name if suspicion status is the same
        final String nameA = a['student']?['profile']?['name'] ?? '';
        final String nameB = b['student']?['profile']?['name'] ?? '';
        return nameA.compareTo(nameB);
      }
    });
  }

  void _onManualRequestReceived(Map<String, dynamic> request) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = null;
      final index = _manualRequests.indexWhere(
        (r) => r['slug'] == request['slug'],
      );
      if (index == -1) _manualRequests.insert(0, request);
    });
  }

  void _onSessionEnded() {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Session has ended.")));
      Navigator.of(context).pop();
    }
  }

  // --- UI Action Handlers ---
  void _handleManualApproval(Map<String, dynamic> request) {
    // Optimistic UI Update
    setState(() {
      _manualRequests.remove(request);
      // Mark as present and add to default list
      request['is_present'] = true;
      _defaultStudents.insert(0, request);
      _activeStudentCount = _defaultStudents.length;
    });

    // Send request to server
    _socketService.approveManualRequests(
      sessionId: widget.sessionData['session_id'],
      authToken: _authToken!,
      attendanceSlugs: [request['slug']],
    );
  }

  void _handleMarkAsAbsent(Map<String, dynamic> student) {
    // Optimistic UI Update
    setState(() {
      _defaultStudents.remove(student);
      _activeStudentCount = _defaultStudents.length;
    });

    // Send request to server
    _socketService.updateStudentAttendance(
      sessionId: widget.sessionData['session_id'],
      authToken: _authToken!,
      attendanceSlug: student['slug'],
      isPresent: false,
    );
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) sub.cancel();
    _socketService.disconnect();
    _sessionService.endSession();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          'Live Session (Active: $_activeStudentCount)',
          style: const TextStyle(color: Colors.black87, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.primaryColor,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: theme.primaryColor,
          tabs: [
            const Tab(text: 'Default'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Manual'),
                  if (_manualRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: theme.primaryColor,
                      child: Text(
                        _manualRequests.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildContent(_buildDefaultStudentList),
          _buildContent(_buildManualRequestList),
        ],
      ),
      floatingActionButton:
          _tabController.index == 1 && _manualRequests.isNotEmpty
              ? FloatingActionButton.extended(
                onPressed: () {
                  final slugsToApprove =
                      _manualRequests.map((r) => r['slug'] as String).toList();
                  _socketService.approveManualRequests(
                    sessionId: widget.sessionData['session_id'],
                    authToken: _authToken!,
                    attendanceSlugs: slugsToApprove,
                  );
                  // Optimistic update
                  setState(() {
                    _defaultStudents.addAll(_manualRequests);
                    _manualRequests.clear();
                    _activeStudentCount = _defaultStudents.length;
                  });
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Mark All Present'),
              )
              : null,
      persistentFooterButtons: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End Session'),
              onPressed: () {
                _socketService.endSession(
                  sessionId: widget.sessionData['session_id'],
                  authToken: _authToken!,
                );
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(Widget Function() contentBuilder) {
    if (_isLoading) return const ListLoadingShimmer();
    if (_errorMessage != null)
      return Center(
        child: Text(
          'Error: $_errorMessage',
          style: const TextStyle(color: Colors.red),
        ),
      );
    return contentBuilder();
  }

  // --- NEW MODERN UI BUILDERS ---

  Widget _buildDefaultStudentList() {
    if (_defaultStudents.isEmpty)
      return const Center(child: Text('No students marked present.'));

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _defaultStudents.length,
      itemBuilder: (context, index) {
        final student = _defaultStudents[index];
        final bool isSuspicious = student['isSuspicious'] ?? false;

        final double ncc = (student['ncc'] as num?)?.toDouble() ?? 0.0;
        final double magnitude =
            (student['magnitude'] as num?)?.toDouble() ?? 0.0;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          // --- ENHANCED STYLING FOR SUSPICIOUS CARDS ---
          elevation: isSuspicious ? 4.0 : 1.5,
          color: Colors.white, // Subtle red background tint
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            // A prominent red border that is impossible to miss
            side: BorderSide(
              color: isSuspicious ? Colors.red.shade300 : Colors.transparent,
              width: 3,
            ),
          ),
          // --- END ENHANCED STYLING ---
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        student['student']?['profile']?['name'] ??
                            'Unknown Student',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Checkbox(
                      value: student['is_present'] ?? false,
                      onChanged: (value) {
                        if (value == false) {
                          _handleMarkAsAbsent(student);
                        }
                      },
                    ),
                  ],
                ),

                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetric('GPS Dist', student['gps_distance']),
                    _buildMetric(
                      'NCC',
                      student['ncc'],
                      isSuspicious: ncc < 0.5,
                    ),
                    _buildMetric(
                      'Magnitude',
                      student['magnitude'],
                      isSuspicious: magnitude < 0.02,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetric(
    String label,
    dynamic value, {
    bool isSuspicious = false,
  }) {
    // Use a consistent red color for the alert text
    final Color valueColor =
        isSuspicious ? Colors.red.shade700 : Colors.black87;
    final FontWeight fontWeight =
        isSuspicious ? FontWeight.w900 : FontWeight.bold;

    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value is num ? value.toStringAsFixed(2) : '-',
          style: TextStyle(
            fontWeight: fontWeight,
            fontSize: 15,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildManualRequestList() {
    if (_manualRequests.isEmpty)
      return const Center(child: Text('No manual attendance requests.'));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _manualRequests.length,
      itemBuilder: (context, index) {
        final request = _manualRequests[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 16,
            ),
            title: Text(
              request['student']?['profile']?['name'] ?? 'Unknown Student',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'Reason: ${request['regulization_comment'] ?? 'No comment'}',
              ),
            ),
            trailing: Checkbox(
              value: false, // Always starts unchecked
              onChanged: (value) {
                if (value == true) {
                  _handleManualApproval(request);
                }
              },
            ),
          ),
        );
      },
    );
  }
}

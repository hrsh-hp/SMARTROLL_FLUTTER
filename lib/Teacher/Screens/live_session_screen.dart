// lib/Teacher/Screens/live_session_screen.dart

import 'package:flutter/material.dart';
import 'package:smartroll/Teacher/services/session_service.dart';

class LiveSessionScreen extends StatefulWidget {
  // This screen receives the full session data from the API
  final Map<String, dynamic> sessionData;

  const LiveSessionScreen({super.key, required this.sessionData});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  final SessionService _sessionService = SessionService.instance;

  @override
  void initState() {
    super.initState();
    // --- CHANGE 1: START THE REAL AUDIO STREAM ---
    // When this screen becomes active, we start the microphone recording stream.
    debugPrint("LiveSessionScreen is now active. Starting real audio stream.");
    _sessionService.startRealAudioStream();
  }

  @override
  void dispose() {
    // CRITICAL: Ensure the audio stops when this screen is closed for any reason.
    debugPrint("LiveSessionScreen is being disposed. Ending session audio.");
    _sessionService.endSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Extract some data to display
    final subjectName =
        widget.sessionData['lecture']['subject']['subject_map']['subject_name'];
    final studentCount = widget.sessionData['student_count'];

    return Scaffold(
      appBar: AppBar(
        title: Text(subjectName, overflow: TextOverflow.ellipsis),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.mic, color: Colors.red),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live Attendance',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Total Students in Class: $studentCount'),
            const Divider(height: 32),
            const Center(
              child: Text(
                'Attendee list will appear here in real-time.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            // TODO: Add the real-time list of attendees here
          ],
        ),
      ),
      // Use a persistent footer button to end the session
      persistentFooterButtons: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End Session'),
              onPressed: () {
                // TODO: Call backend API to mark session as 'post'
                // The dispose method will handle stopping the audio.
                Navigator.of(context).pop(); // Go back to the dashboard
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

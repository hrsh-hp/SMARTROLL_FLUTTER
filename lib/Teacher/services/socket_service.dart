// lib/Teacher/Services/socket_service.dart (Create this new file)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:smartroll/Common/utils/constants.dart'; // For your socket_url

class SocketService {
  // Singleton setup
  SocketService._privateConstructor();
  static final SocketService instance = SocketService._privateConstructor();

  IO.Socket? _socket;

  // StreamControllers to broadcast data to the UI
  final _defaultStudentsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _manualRequestsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _activeStudentCountController = StreamController<int>.broadcast();
  final _sessionEndedController = StreamController<void>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Streams for the UI to listen to
  Stream<Map<String, dynamic>> get defaultStudentsStream =>
      _defaultStudentsController.stream;
  Stream<Map<String, dynamic>> get manualRequestsStream =>
      _manualRequestsController.stream;
  Stream<int> get activeStudentCountStream =>
      _activeStudentCountController.stream;
  Stream<void> get sessionEndedStream => _sessionEndedController.stream;
  Stream<String> get errorStream => _errorController.stream;

  void connectAndListen({
    required String sessionId,
    required String authToken,
  }) {
    // Disconnect any existing socket
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
    }

    _socket = IO.io('$backendBaseUrl/client', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'withCredentials': true,
    });

    _socket!.onConnect((_) {
      debugPrint('✅ Socket connected. Emitting handshake.');
      _socket!.emit('socket_connection', {
        'client': 'FE', // Flutter Emitter
        'session_id': sessionId,
        'auth_token': authToken,
      });
    });

    // --- LISTEN TO ALL SERVER EVENTS ---

    _socket!.on('ongoing_session_data', (data) {
      debugPrint('Received ongoing_session_data');
      final sessionDetails = data['data']['data']['data'];
      final List markedAttendances =
          (sessionDetails['marked_attendances'] as List?) ?? [];
      final List pendingRequests =
          (sessionDetails['pending_regulization_requests'] as List?) ?? [];

      for (var student in markedAttendances) {
        _defaultStudentsController.add(student);
      }
      for (var request in pendingRequests) {
        _manualRequestsController.add(request);
      }
      _activeStudentCountController.add(markedAttendances.length);
    });

    _socket!.on('mark_attendance', (data) {
      debugPrint('Received mark_attendance');
      final attendanceData = data['data']['data']['data']['attendance_data'];
      if (attendanceData != null) {
        _defaultStudentsController.add(attendanceData);
      }
    });

    _socket!.on('regulization_request', (data) {
      debugPrint('Received regulization_request');
      final manualData = data['data']['data']['data']['attendance_data'];
      if (manualData != null) {
        _manualRequestsController.add(manualData);
      }
    });

    _socket!.on('regulization_approved', (data) {
      debugPrint('Received regulization_approved');
      final List<dynamic>? approvedStudents = data?['data']?['data']?['data'];
      if (approvedStudents != null) {
        for (var student in approvedStudents) {
          _defaultStudentsController.add(student);
        }
      }
    });

    // This listener handles the server's confirmation after we update an attendance record.
    // We can use this to show a success/error toast.
    _socket!.on('update_attendance', (data) {
      final message = data?['message'];
      final statusCode = data?['status_code'];
      if (statusCode == 200) {
        debugPrint("Attendance updated successfully: $message");
        // Optionally show a success toast here.
      } else {
        debugPrint("Failed to update attendance: $message");
        // Optionally show an error toast and revert the UI change.
      }
    });

    _socket!.on('session_ended', (data) {
      debugPrint('Received session_ended');
      _sessionEndedController.add(null);
      disconnect();
    });

    _socket!.on('client_error', (data) {
      debugPrint('Received client_error: ${data['data']}');
      _errorController.add(
        data['data']?.toString() ?? 'An unknown server error occurred.',
      );
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket disconnected.');
    });
  }

  // --- METHODS TO EMIT DATA TO SERVER ---

  void sendAudioChunk({
    required String sessionId,
    required String authToken,
    required Uint8List wavBlob,
  }) {
    if (_socket?.connected ?? false) {
      _socket!.emit('incoming_audio_chunks', {
        'client': 'FE',
        'session_id': sessionId,
        'auth_token': authToken,
        'blob': wavBlob, // socket.io client handles binary data correctly
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  void approveManualRequests({
    required String sessionId,
    required String authToken,
    required List<String> attendanceSlugs,
  }) {
    if (_socket?.connected ?? false) {
      _socket!.emit('regulization_request', {
        'client': 'FE',
        'session_id': sessionId,
        'data': attendanceSlugs,
        'auth_token': authToken,
      });
    }
  }

  /// Emits a request to update a single student's attendance status (e.g., mark as absent).
  void updateStudentAttendance({
    required String sessionId,
    required String authToken,
    required String attendanceSlug,
    required bool isPresent, // The new status (e.g., false if unchecking)
  }) {
    if (_socket?.connected ?? false) {
      _socket!.emit('update_attendance', {
        'client': 'FE',
        'attendance_slug': attendanceSlug,
        'session_id': sessionId,
        'auth_token': authToken,
        'action': isPresent,
      });
    }
  }

  void endSession({required String sessionId, required String authToken}) {
    if (_socket?.connected ?? false) {
      _socket!.emit('session_ended', {
        'client': 'FE',
        'session_id': sessionId,
        'auth_token': authToken,
      });
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

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

  bool _isDisconnectingGracefully = false;

  // Variable to store the specific error message ---
  String? _lastKnownError;

  void connectAndListen({
    required String sessionId,
    required String authToken,
  }) {
    // Disconnect any existing socket
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
      // debugPrint('Disconnecting existing socket before reconnecting.');
    }

    _isDisconnectingGracefully = false;
    _lastKnownError = null; // Reset the last known error

    _socket = IO.io('$backendBaseUrl/client', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'withCredentials': true,
      'reconnection': true,
      'reconnectionAttempts': 5 , // Try to reconnect 5 times
      'reconnectionDelay': 2000, // Wait 2 seconds before each reconnection
      'reconnectionDelayMax': 5000, // Max delay of 5 seconds
      'timeout': 10000, // 10 seconds timeout for connection
      'forceNew': true, // Force a new connection
    });

    // _socket!.onAny((event, data) {
    //   debugPrint('SOCKET DEBUG :: Event: $event, Data: $data');
    // });

    _socket!.on('connect_error', (error) {
      debugPrint("❌ Socket Connect Error: $error");
      // The error object often contains the server's message.
      // We default to a clear message if it's a generic network error.
      final errorMessage =
          error.toString().contains('Another teacher')
              ? "Another teacher is already in the session."
              : "Failed to connect to the session.";
      debugPrint('Socket connection error: $errorMessage');
      disconnect();
    });

    _socket!.onConnect((_) {
      debugPrint('✅ Socket connected. Emitting handshake.');
      _socket!.emit('socket_connection', {
        'client': 'FE',
        'session_id': sessionId,
        'auth_token': authToken,
      });
    });

    // --- LISTEN TO ALL SERVER EVENTS ---

    _socket!.on('ongoing_session_data', (data) {
      debugPrint('Received ongoing_session_data');
      debugPrint('Data: ${data['data']['data']['data']['marked_attendances']}');
      final sessionDetails = data['data']['data']['data'];
      final List markedAttendances =
          (sessionDetails['marked_attendances'] as List?) ?? [];
      final List pendingRequests =
          (sessionDetails['pending_regulization_requests'] as List?) ?? [];

      for (var student in markedAttendances) {
        _defaultStudentsController.add(student);
        debugPrint('Adding student: $_defaultStudentsController');
      }
      for (var request in pendingRequests) {
        _manualRequestsController.add(request);
      }
      _activeStudentCountController.add(markedAttendances.length);
    });

    _socket!.on('mark_attendance', (data) {
      debugPrint('Received mark_attendance');
      final attendanceData = data['data']['data']['attendance_data'];
      if (attendanceData != null) {
        _defaultStudentsController.add(attendanceData);
      }
    });

    _socket!.on('regulization_request', (data) {
      debugPrint('Received regulization_request');
      final manualData = data['data']['data']['attendance_data'];
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
      final errorMessage =
          data?['data']?.toString() ?? 'An unknown server error occurred.';
      debugPrint('Received client_error, storing message: "$errorMessage"');
      _lastKnownError = errorMessage;
    });

    _socket!.onDisconnect((_) async {
      debugPrint(
        'Socket disconnected. Waiting briefly to resolve final error state...',
      );
      if (_isDisconnectingGracefully) return;

      // Wait for a moment to allow any pending client_error to be processed.
      await Future.delayed(const Duration(milliseconds: 6000));

      if (_lastKnownError != null) {
        _errorController.add(_lastKnownError!);
        debugPrint('Pushing specific error to UI: "$_lastKnownError"');
      } else {
        _errorController.add('Connection to session lost unexpectedly.');
        debugPrint('Pushing generic disconnect error to UI.');
      }
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
    _isDisconnectingGracefully = true;
    _socket?.disconnect();
    _socket = null;
  }
}

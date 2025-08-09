// lib/Teacher/Services/socket_service.dart (Create this new file)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:smartroll/Common/utils/constants.dart'; // For your socket_url

enum SocketConnectionState { connected, reconnecting, failed }

class SocketService {
  // Singleton setup
  SocketService._privateConstructor();
  static final SocketService instance = SocketService._privateConstructor();

  IO.Socket? _socket;
  Completer<Map<String, dynamic>>? _connectionCompleter;

  final _connectionStateController =
      StreamController<SocketConnectionState>.broadcast();
  Stream<SocketConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

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

  Future<Map<String, dynamic>> connectAndListen({
    required String sessionId,
    required String authToken,
  }) {
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      return _connectionCompleter!.future;
    }
    _connectionCompleter = Completer<Map<String, dynamic>>();

    // Disconnect any existing socket
    if (_socket != null) _socket!.dispose();

    _socket = IO.io('$backendBaseUrl/client', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false, // We will connect manually
      'withCredentials': true,
      'forceNew': true, // Force a new connection
      'reconnection': true,
      'reconnectionAttempts': 5, // Try to reconnect 5 times
      'reconnectionDelay': 2000, // Wait 2 seconds before each reconnection
      'reconnectionDelayMax': 5000, // Max delay of 5 seconds
      'timeout': 10000, // 10 seconds timeout for connection
    });

    _socket!.on('connect_error', (error) {
      debugPrint("❌ Socket Connect Error: $error");
      final errorMessage =
          error.toString().contains('Another teacher')
              ? "Another teacher is already in the session."
              : "Failed to connect to the session server.";
      if (!_connectionCompleter!.isCompleted) {
        _connectionCompleter!.completeError(UserFacingException(errorMessage));
      }
    });

    _socket!.onConnect((_) {
      debugPrint('✅ Socket connected. Emitting handshake.');
      _connectionStateController.add(SocketConnectionState.connected);
      _socket!.emit('socket_connection', {
        'client': 'FE',
        'session_id': sessionId,
        'auth_token': authToken,
      });
    });

    _socket!.on('reconnect', (attemptNumber) {
      debugPrint('✅ Socket reconnected on attempt $attemptNumber.');
      _connectionStateController.add(SocketConnectionState.connected);
      // Re-emit handshake to ensure server recognizes the new connection
      _socket!.emit('socket_connection', {
        'client': 'FE',
        'session_id': sessionId,
        'auth_token': authToken,
      });
    });

    _socket!.on('reconnecting', (attemptNumber) {
      debugPrint('Socket reconnecting... attempt $attemptNumber');
      _connectionStateController.add(SocketConnectionState.reconnecting);
    });

    _socket!.on('reconnect_failed', (_) {
      debugPrint('❌ All reconnection attempts failed.');
      _connectionStateController.add(SocketConnectionState.failed);
      _errorController.add(
        "Could not reconnect to the session. Please try again.",
      );
    });

    // --- LISTEN TO ALL SERVER EVENTS ---

    _socket!.on('ongoing_session_data', (data) {
      debugPrint('Received ongoing_session_data, connection successful.');

      final Map<String, dynamic>? sessionDetails =
          data?['data']?['data']?['data'];
      if (sessionDetails == null) {
        if (!_connectionCompleter!.isCompleted) {
          _connectionCompleter!.completeError(
            UserFacingException("Invalid initial data from server."),
          );
        }
        return;
      }

      final List markedAttendances =
          (sessionDetails['marked_attendances'] as List?) ?? [];
      final List pendingRequests =
          (sessionDetails['pending_regulization_requests'] as List?) ?? [];

      // We do NOT push this to the streams. The streams are for LIVE updates only.
      // Instead, we complete the Future with this payload.
      if (!_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete({
          'default': markedAttendances,
          'manual': pendingRequests,
          'count': markedAttendances.length,
        });
      }
      // debugPrint('Received ongoing_session_data');
      // debugPrint('Data: ${data['data']['data']['data']['marked_attendances']}');
      // final sessionDetails = data['data']['data']['data'];
      // final List markedAttendances =
      //     (sessionDetails['marked_attendances'] as List?) ?? [];
      // final List pendingRequests =
      //     (sessionDetails['pending_regulization_requests'] as List?) ?? [];

      // for (var student in markedAttendances) {
      //   _defaultStudentsController.add(student);
      //   debugPrint('Adding student: $_defaultStudentsController');
      // }
      // for (var request in pendingRequests) {
      //   _manualRequestsController.add(request);
      // }
      // _activeStudentCountController.add(markedAttendances.length);
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
      final manualData = data?['data']?['data']?['data']?['attendance_data'];
      if (manualData != null) {
        _manualRequestsController.add(manualData);
      }
    });

    _socket!.on('regulization_approved', (data) {
      debugPrint('Received regulization_approved');
      final List<dynamic>? approvedStudents = data?['data']?['data']?['data'];
      debugPrint(approvedStudents.toString());
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
      debugPrint("Received client_error during handshake phase.");
      // debugPrint("Data: ${data.data}");
      final decodedData = data is String ? jsonDecode(data) : data;
      final errorMessage =
          decodedData['data']?.toString() ??
          'An unknown server error occurred.';
      // If the handshake is still pending, this is a fatal error.
      if (!_connectionCompleter!.isCompleted) {
        _connectionCompleter!.completeError(UserFacingException(errorMessage));
      } else {
        // If the handshake is already complete, push to the live error stream.
        _errorController.add(errorMessage);
      }
      // if (data?['status_code'] == 500) {
      //   // Handle specific error code if needed
      //   debugPrint('Received 500 error, disconnecting socket.');
      //   disconnect();
      //   // _errorController.add(errorMessage);
      // }
    });

    _socket!.onDisconnect((_) async {
      debugPrint('Socket disconnected ');
      if (_connectionCompleter?.isCompleted ?? false) {
        _connectionStateController.add(SocketConnectionState.reconnecting);
      } else {
        // This handles disconnects during the initial handshake
        if (!_connectionCompleter!.isCompleted) {
          _connectionCompleter!.completeError("Connection lost unexpectedly.");
        }
      }
      // Wait for a moment to allow any pending client_error to be processed.
      // await Future.delayed(const Duration(milliseconds: 6000));

      // if (_lastKnownError != null) {
      //   _errorController.add(_lastKnownError!);
      //   debugPrint('Pushing specific error to UI: "$_lastKnownError"');
      // } else {
      //   _errorController.add('Connection to session lost unexpectedly.');
      //   debugPrint('Pushing generic disconnect error to UI.');
      // }
    });

    _socket!.connect();
    return _connectionCompleter!.future;
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

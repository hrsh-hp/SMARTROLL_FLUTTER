import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smartroll/Common/utils/constants.dart';
import 'package:smartroll/Teacher/utils/teacher_audio_recorder.dart'; // Import the recorder

enum SessionState { none, starting, active, error }

class SessionService {
  SessionService._privateConstructor();
  static final SessionService instance = SessionService._privateConstructor();

  // State for the ultrasonic chirp player
  final AudioPlayer _chirpPlayer = AudioPlayer();
  String? _tempChirpFilePath;

  // State for the teacher's microphone recorder
  final TeacherAudioRecorder _micRecorder = TeacherAudioRecorder();
  StreamSubscription<Uint8List>? _micStreamSubscription;

  // Public state for the UI
  final ValueNotifier<SessionState> sessionState = ValueNotifier(
    SessionState.none,
  );
  String? currentSessionId;
  String? errorMessage;

  /// Starts a new lecture session, including the ultrasonic chirp.
  /// Returns the session data from the backend on success.
  Future<Map<String, dynamic>> startSession({
    required String lectureSlug,
    required String classroomSlug,
  }) async {
    if (sessionState.value == SessionState.starting ||
        sessionState.value == SessionState.active) {
      throw SessionServiceException('Another session is already active.');
    }
    await endSession(); // Defensively clean up any previous state

    sessionState.value = SessionState.starting;
    errorMessage = null;

    try {
      final sessionData = await _createSessionAPI(lectureSlug, classroomSlug);
      currentSessionId = sessionData['session_id'];
      final String audioUrlPath = sessionData['audio_url'];
      final Uint8List flacBytes = await _fetchAudioAPI(audioUrlPath);

      _tempChirpFilePath = await _saveBytesToTempFile(
        flacBytes,
        currentSessionId!,
      );
      await _playChirpFromFile(_tempChirpFilePath!);
      sessionState.value = SessionState.active;
      debugPrint("✅ Session started successfully. Playing ultrasonic chirp.");
      return sessionData;
    } on SessionServiceException catch (e) {
      debugPrint("❌ Failed to start session: ${e.runtimeType}: ${e.message}");
      errorMessage = e.message;
      sessionState.value = SessionState.error;
      await endSession();
      rethrow;
    } catch (e) {
      debugPrint("❌ Failed to start session with an unexpected error: $e");
      errorMessage = "An unexpected error occurred: ${e.toString()}";
      sessionState.value = SessionState.error;
      await endSession();
      throw SessionServiceException(
        "An unexpected error occurred: ${e.toString()}",
      );
    }
  }

  /// Starts the teacher's microphone recording and provides chunks via a callback.
  void startRealAudioStream({required Function(Uint8List) onAudioChunk}) {
    stopRealAudioStream(); // Ensure any previous stream is stopped
    try {
      final audioStream = _micRecorder.startRecording();
      _micStreamSubscription = audioStream.listen(
        onAudioChunk,
        onError: (error) {
          throw RecordingException(
            "Error in microphone stream: ${error.toString()}",
          );
        },
      );
      debugPrint("✅ Teacher microphone recording stream started.");
    } catch (e) {
      throw RecordingException(
        "Failed to start microphone recording: ${e.toString()}",
      );
    }
  }

  /// Stops the teacher's microphone recording stream.
  void stopRealAudioStream() {
    _micStreamSubscription?.cancel();
    _micStreamSubscription = null;
    // The recorder itself is stopped when its stream subscription is cancelled.
  }

  /// The master cleanup method. Stops all audio, cleans files, and resets state.
  Future<void> endSession() async {
    // Stop both audio sources
    stopRealAudioStream();
    if (_chirpPlayer.state == PlayerState.playing) {
      await _chirpPlayer.stop();
    }

    // Clean up the temporary chirp file
    if (_tempChirpFilePath != null) {
      try {
        final tempFile = File(_tempChirpFilePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        debugPrint("⚠️ Error deleting temp chirp file: $e");
      }
      _tempChirpFilePath = null;
    }

    // Reset state
    currentSessionId = null;
    sessionState.value = SessionState.none;
    debugPrint("⏹️ Session ended and all resources released.");
  }

  // --- Private Helper Methods ---

  Future<Map<String, dynamic>> _createSessionAPI(
    String lectureSlug,
    String classroomSlug,
  ) async {
    final String? token = await secureStorage.read(key: 'accessToken');
    if (token == null) {
      throw NetworkException('Authentication token not found.');
    }

    final url = Uri.parse(
      '$backendBaseUrl/api/manage/session/create_lecture_session/',
    );
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'lecture_slug': lectureSlug,
          'classroom_slug': classroomSlug,
        }),
      );
      final decodedBody = jsonDecode(response.body);
      if (response.statusCode == 200 && decodedBody['error'] == false) {
        return decodedBody['data'];
      } else {
        throw NetworkException(
          decodedBody['message'] ?? 'Backend returned an error.',
        );
      }
    } on SocketException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } catch (e) {
      throw NetworkException('Failed to create session: ${e.toString()}');
    }
  }

  Future<Uint8List> _fetchAudioAPI(String audioUrlPath) async {
    final url = Uri.parse('$backendBaseUrl/api/media/$audioUrlPath');
    debugPrint("Attempting to fetch audio from this exact URL: $url");
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        debugPrint(
          "✅ [DOWNLOAD] Successfully downloaded ${response.bodyBytes.length} bytes from $url",
        );
        return response.bodyBytes;
      } else {
        throw NetworkException(
          'Failed to download audio chirp. Status: ${response.statusCode}',
        );
      }
    } on SocketException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } catch (e) {
      throw NetworkException('Failed to fetch audio: ${e.toString()}');
    }
  }

  Future<String> _saveBytesToTempFile(Uint8List bytes, String sessionId) async {
    final tempDir = await getTemporaryDirectory();
    // Use a unique name to avoid conflicts
    final filePath = '${tempDir.path}/chirp_$sessionId.flac';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    debugPrint("✅ [FILE WRITE] Saved ${bytes.length} bytes to: $filePath");

    return filePath;
  }

  // --- UPDATED HELPER METHOD: Play from file ---
  Future<void> _playChirpFromFile(String filePath) async {
    try {
      await _chirpPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _chirpPlayer.setReleaseMode(ReleaseMode.loop);
      await _chirpPlayer.setVolume(0.8);
      await _chirpPlayer.play(DeviceFileSource(filePath));
    } catch (e) {
      throw AudioPlaybackException(
        "Error playing chirp from file: $filePath. Details: ${e.toString()}",
      );
    }
  }

  void dispose() {
    _chirpPlayer.dispose();
    sessionState.dispose();
  }
}

/// A custom AudioSource for the `just_audio` package that plays from a Uint8List.

// Custom Exceptions for SessionService
class SessionServiceException implements Exception {
  final String message;
  SessionServiceException(this.message);

  @override
  String toString() => 'SessionServiceException: $message';
}

class AudioInitializationException extends SessionServiceException {
  AudioInitializationException(super.message);
}

class RecordingException extends SessionServiceException {
  RecordingException(super.message);
}

class AudioPlaybackException extends SessionServiceException {
  AudioPlaybackException(super.message);
}

class NetworkException extends SessionServiceException {
  NetworkException(super.message);
}

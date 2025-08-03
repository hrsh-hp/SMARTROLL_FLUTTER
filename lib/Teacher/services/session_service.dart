import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smartroll/Common/utils/constants.dart'; // For secureStorage and backendBaseUrl

// Enum to represent the possible states of a session
enum SessionState { none, starting, active, error }

class SessionService {
  // Singleton pattern to ensure only one instance of the service exists
  SessionService._privateConstructor();
  static final SessionService instance = SessionService._privateConstructor();

  final AudioPlayer _audioPlayer = AudioPlayer();

  // ValueNotifier will notify listeners (like your UI) when the state changes
  final ValueNotifier<SessionState> sessionState = ValueNotifier(
    SessionState.none,
  );
  String? currentSessionId;
  String? errorMessage;
  String? _tempAudioFilePath;

  /// Starts a new lecture session.
  ///
  /// This function orchestrates the entire process:
  /// 1. Calls the backend to create a session.
  /// 2. Fetches the ultrasonic audio chirp.
  /// 3. Plays the audio in a loop at 80% volume.
  Future<Map<String, dynamic>> startSession({
    required String lectureSlug,
    required String classroomSlug,
  }) async {
    if (sessionState.value == SessionState.starting ||
        sessionState.value == SessionState.active) {
      debugPrint("Session is already starting or active.");
      throw 'Another session is already active.';
    }
    await endSession();

    sessionState.value = SessionState.starting;
    errorMessage = null;

    try {
      // --- Step 1: Create the session via API ---
      final sessionData = await _createSessionAPI(lectureSlug, classroomSlug);
      currentSessionId = sessionData['session_id'];
      final String audioUrlPath = sessionData['audio_url'];

      // --- Step 2: Fetch the audio file as bytes ---
      final Uint8List audioBytes = await _fetchAudioAPI(audioUrlPath);
      _tempAudioFilePath = await _saveBytesToTempFile(
        audioBytes,
        currentSessionId!,
      );

      // --- Step 3: Configure and play the audio ---
      await _playChirpFromFile(_tempAudioFilePath!);
      sessionState.value = SessionState.active;
      debugPrint("Session started successfully. Playing audio chirp.");
      return sessionData;
    } catch (e) {
      debugPrint("Failed to start session: $e");
      errorMessage = e.toString();
      sessionState.value = SessionState.error;
      await endSession(); // Clean up resources on failure
      throw e;
    }
  }

  /// Ends the current session and stops all related activities.
  Future<void> endSession() async {
    // Check if the player is still active before trying to stop it.
    if (_audioPlayer.playing) {
      await _audioPlayer.stop();
    }

    currentSessionId = null;
    sessionState.value = SessionState.none;
    if (_tempAudioFilePath != null) {
      try {
        final tempFile = File(_tempAudioFilePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
          debugPrint("Cleaned up temporary audio file: $_tempAudioFilePath");
        }
      } catch (e) {
        debugPrint("Error deleting temp file: $e");
      }
      _tempAudioFilePath = null;
    }
    debugPrint("Session ended and audio stopped.");
    // NOTE: You might want to call a backend endpoint here to formally end the session
  }

  // --- Private Helper Methods ---

  Future<Map<String, dynamic>> _createSessionAPI(
    String lectureSlug,
    String classroomSlug,
  ) async {
    final String? token = await secureStorage.read(key: 'accessToken');
    if (token == null) throw 'Authentication token not found.';

    final url = Uri.parse(
      '$backendBaseUrl/api/manage/session/create_lecture_session/',
    );
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

    if (response.statusCode == 200) {
      final decodedBody = jsonDecode(response.body);
      if (decodedBody['error'] == false) {
        return decodedBody['data'];
      } else {
        throw decodedBody['message'] ?? 'Backend returned an error.';
      }
    } else {
      throw 'Failed to create session. Status: ${response.statusCode}';
    }
  }

  Future<Uint8List> _fetchAudioAPI(String audioUrlPath) async {
    // The base URL for media might be different, adjust if needed.
    // Assuming it's the same base URL for now.
    final url = Uri.parse('$backendBaseUrl/api/media/$audioUrlPath');
    debugPrint("Attempting to fetch audio from this exact URL: $url");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      debugPrint(
        "✅ [DOWNLOAD] Successfully downloaded ${response.bodyBytes.length} bytes from $url",
      );
      return response.bodyBytes;
    } else {
      throw 'Failed to download audio chirp. Status: ${response.statusCode}';
    }
  }

  Future<String> _saveBytesToTempFile(Uint8List bytes, String sessionId) async {
    final tempDir = await getTemporaryDirectory();
    // Use a unique name to avoid conflicts
    final filePath = '${tempDir.path}/chirp_$sessionId.wav';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    debugPrint("✅ [FILE WRITE] Saved ${bytes.length} bytes to: $filePath");

    return filePath;
  }

  // --- UPDATED HELPER METHOD: Play from file ---
  Future<void> _playChirpFromFile(String filePath) async {
    debugPrint("▶️ [PLAYER] Telling just_audio to play from: $filePath");
    // This is much simpler than using a custom source
    await _audioPlayer.setFilePath(filePath);
    await _audioPlayer.setLoopMode(LoopMode.one);
    await _audioPlayer.setVolume(0.8);
    _audioPlayer.play();
  }
}

/// A custom AudioSource for the `just_audio` package that plays from a Uint8List.

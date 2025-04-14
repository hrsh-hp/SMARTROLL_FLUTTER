import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:record/record.dart';

// --- Result Status Enum ---
enum AttendanceDataStatus {
  success,
  locationPermissionDenied,
  locationPermissionDeniedForever,
  locationServiceDisabled,
  locationTimeout,
  locationError,
  locationIsMocked, // <-- ADDED
  microphonePermissionDenied,
  microphonePermissionDeniedForever,
  recordingError,
  unknownError,
}

// --- Result Class ---
class AttendanceDataResult {
  final LocationData? locationData;
  final Uint8List? audioBytes; // WAV blob
  final AttendanceDataStatus status;
  final String? errorMessage;

  AttendanceDataResult({
    this.locationData,
    this.audioBytes,
    required this.status,
    this.errorMessage,
  });
}

// --- The Combined Collector Service ---
class AttendanceDataCollector {
  final Location _location = Location();
  final AudioRecorder _audioRecorder = AudioRecorder();

  /// Collects location and records audio concurrently.
  /// Handles permissions and service checks internally.
  Future<AttendanceDataResult> collectData({
    Duration recordingDuration = const Duration(seconds: 10),
  }) async {
    // --- 1. Check & Request Permissions ---
    final permissionStatus = await _checkAndRequestPermissions();
    if (permissionStatus != AttendanceDataStatus.success) {
      return AttendanceDataResult(
        status: permissionStatus,
        errorMessage: _getPermissionErrorMessage(permissionStatus),
      );
    }

    // --- 2. Check Location Service ---
    // Moved service check inside _getLocationInternal for better flow control
    debugPrint("Permissions granted. Starting data collection...");

    // --- 3. Collect Location and Audio Concurrently ---
    try {
      final results = await Future.wait([
        _getLocationInternal(), // Task 1: Get Location (includes service check)
        _recordAudio(recordingDuration), // Task 2: Record Audio
      ]).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          // Overall timeout for both tasks
          debugPrint("Data collection (location+audio) timed out.");
          // Return a specific timeout status if the combined operation times out
          throw TimeoutException('Data collection timed out');
        },
      );

      // --- 4. Process Results ---
      final locationResult = results[0]; // Using same result type now
      final audioResult = results[1];

      // Check location result first
      if (locationResult.status != AttendanceDataStatus.success ||
          locationResult.locationData == null) {
        debugPrint("Location collection failed: ${locationResult.status}");
        return locationResult; // Return the specific location error result
      }

      // Check audio result
      if (audioResult.status != AttendanceDataStatus.success ||
          audioResult.audioBytes == null) {
        debugPrint("Audio recording failed: ${audioResult.status}");
        return audioResult; // Return the specific audio error result
      }

      // --- Success ---
      debugPrint("Location and Audio collected successfully.");
      return AttendanceDataResult(
        status: AttendanceDataStatus.success,
        locationData: locationResult.locationData,
        audioBytes: audioResult.audioBytes,
      );
    } on TimeoutException {
      return AttendanceDataResult(
        status:
            AttendanceDataStatus
                .locationTimeout, // Or a new combined timeout status
        errorMessage: "Data collection timed out.",
      );
    } catch (e) {
      debugPrint("Unexpected error during data collection: $e");
      return AttendanceDataResult(
        status: AttendanceDataStatus.unknownError,
        errorMessage: "An unexpected error occurred: ${e.toString()}",
      );
    } finally {
      // Ensure recorder is stopped and disposed if still active
      await _disposeRecorder();
    }
  }

  /// Checks and requests necessary permissions (Location & Microphone).
  Future<AttendanceDataStatus> _checkAndRequestPermissions() async {
    Map<ph.Permission, ph.PermissionStatus> statuses =
        await [ph.Permission.location, ph.Permission.microphone].request();

    var locationStatus =
        statuses[ph.Permission.location] ?? ph.PermissionStatus.denied;
    if (locationStatus.isPermanentlyDenied) {
      return AttendanceDataStatus.locationPermissionDeniedForever;
    }
    if (!locationStatus.isGranted) {
      return AttendanceDataStatus.locationPermissionDenied;
    }

    var microphoneStatus =
        statuses[ph.Permission.microphone] ?? ph.PermissionStatus.denied;
    if (microphoneStatus.isPermanentlyDenied) {
      return AttendanceDataStatus.microphonePermissionDeniedForever;
    }
    if (!microphoneStatus.isGranted) {
      return AttendanceDataStatus.microphonePermissionDenied;
    }

    return AttendanceDataStatus.success;
  }

  /// Internal helper to get location, including service check and mock detection.
  Future<AttendanceDataResult> _getLocationInternal() async {
    // Check Location Service
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      debugPrint("Location service disabled. Requesting service...");
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        debugPrint("Location service request denied by user.");
        return AttendanceDataResult(
          status: AttendanceDataStatus.locationServiceDisabled,
        );
      }
    }

    // Get Location Data
    debugPrint("Location services OK. Getting location...");
    try {
      await _location.changeSettings(accuracy: LocationAccuracy.high);
      final locationData = await _location.getLocation().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Getting location timed out'),
      );

      // --- Mock Location Check ---
      if (locationData.isMock == true) {
        // Check if explicitly true
        debugPrint("Mock location detected!");
        return AttendanceDataResult(
          status: AttendanceDataStatus.locationIsMocked, // Use the new status
          errorMessage:
              'Mock location detected. Attendance marking disallowed.',
        );
      }

      // Log mock status even if false or null for debugging
      debugPrint(
        "Location fetched: Lat ${locationData.latitude}, Lon ${locationData.longitude}, Mock: ${locationData.isMock}",
      );
      return AttendanceDataResult(
        status: AttendanceDataStatus.success,
        locationData: locationData,
      );
    } on TimeoutException catch (e) {
      return AttendanceDataResult(
        status: AttendanceDataStatus.locationTimeout,
        errorMessage: e.message,
      );
    } catch (e) {
      debugPrint("Error getting location: $e");
      return AttendanceDataResult(
        status: AttendanceDataStatus.locationError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Internal helper to record audio.
  Future<AttendanceDataResult> _recordAudio(Duration duration) async {
    final completer = Completer<AttendanceDataResult>();
    List<int> allBytes = [];
    StreamSubscription? streamSubscription;
    Timer? timer;

    // Use a separate recorder instance for each call to avoid state issues
    final recorder = AudioRecorder();

    try {
      //   should be checked already, but good practice
      if (!await recorder.hasPermission()) {
        return AttendanceDataResult(
          status: AttendanceDataStatus.microphonePermissionDenied,
        );
      }

      debugPrint("Starting audio stream...");
      final stream = await recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.wav),
      );

      streamSubscription = stream.listen(
        (data) => allBytes.addAll(data),
        onDone: () {
          debugPrint("Audio stream finished.");
          timer?.cancel(); // Cancel timer if stream finishes early
          if (!completer.isCompleted) {
            completer.complete(
              AttendanceDataResult(
                status: AttendanceDataStatus.success,
                audioBytes: Uint8List.fromList(allBytes),
              ),
            );
          }
          recorder.dispose(); // Dispose here
        },
        onError: (error) {
          debugPrint("Audio stream error: $error");
          timer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(
              AttendanceDataResult(
                status: AttendanceDataStatus.recordingError,
                errorMessage: "Error during recording: $error",
              ),
            );
          }
          recorder.dispose(); // Dispose here
        },
        cancelOnError: true,
      );

      timer = Timer(duration, () async {
        debugPrint("Audio recording duration reached. Stopping stream...");
        await streamSubscription?.cancel(); // Cancel first
        if (await recorder.isRecording()) {
          await recorder.stop(); // Stop should trigger onDone
        }
        // Safety net if onDone didn't complete quickly
        if (!completer.isCompleted) {
          debugPrint("Completing audio recording from timer.");
          completer.complete(
            AttendanceDataResult(
              status: AttendanceDataStatus.success,
              audioBytes: Uint8List.fromList(allBytes),
            ),
          );
          await recorder.dispose(); // Dispose here
        }
      });

      return completer.future;
    } catch (e) {
      debugPrint("Error starting audio recording: $e");
      timer?.cancel();
      await streamSubscription?.cancel();
      await _disposeRecorder(recorder); // Use helper to dispose
      return AttendanceDataResult(
        status: AttendanceDataStatus.recordingError,
        errorMessage: "Failed to start recording: ${e.toString()}",
      );
    }
  }

  // Helper to safely dispose the recorder instance used in _recordAudio
  Future<void> _disposeRecorder([AudioRecorder? recorderInstance]) async {
    final recorder =
        recorderInstance ?? _audioRecorder; // Use passed instance or default
    try {
      if (await recorder.isRecording() || await recorder.isPaused()) {
        await recorder.stop();
      }
      await recorder.dispose();
      debugPrint("AudioRecorder disposed.");
    } catch (e) {
      debugPrint("Error disposing recorder: $e");
    }
  }

  // Helper to get user-friendly messages for permission errors
  String _getPermissionErrorMessage(AttendanceDataStatus status) {
    switch (status) {
      case AttendanceDataStatus.locationPermissionDenied:
        return 'Location permission is required.';
      case AttendanceDataStatus.locationPermissionDeniedForever:
        return 'Location permission permanently denied. Please enable in settings.';
      case AttendanceDataStatus.microphonePermissionDenied:
        return 'Microphone permission is required.';
      case AttendanceDataStatus.microphonePermissionDeniedForever:
        return 'Microphone permission permanently denied. Please enable in settings.';
      default:
        return 'Required permissions not granted.';
    }
  }

  // Optional: Public dispose method if the service itself holds long-lived resources
  // void dispose() {
  //   _disposeRecorder(); // Dispose the default instance if needed
  // }
}

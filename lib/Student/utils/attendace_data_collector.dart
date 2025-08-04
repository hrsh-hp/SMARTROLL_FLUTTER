import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';
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
  locationIsMocked,
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
  final int? recordingStartTimeMillis;
  final String? errorMessage;

  AttendanceDataResult({
    this.locationData,
    this.audioBytes,
    required this.status,
    this.recordingStartTimeMillis,
    this.errorMessage,
  });
}

// --- The Combined Collector Service ---
class AttendanceDataCollector {
  final Location _location = Location();
  final AudioRecorder _audioRecorder = AudioRecorder();

  /// Checks and requests necessary permissions (Location & Microphone).
  static Future<AttendanceDataStatus> checkAndRequestPermissions({
    String role = "student",
  }) async {
    List<ph.Permission> permissionsToRequest = [];
    if (role == 'student') {
      permissionsToRequest.add(ph.Permission.location);
      permissionsToRequest.add(ph.Permission.microphone);
    } else if (role == 'teacher') {
      permissionsToRequest.add(ph.Permission.microphone);
    }

    if (permissionsToRequest.isEmpty) {
      return AttendanceDataStatus.success;
    }

    Map<ph.Permission, ph.PermissionStatus> statuses =
        await permissionsToRequest.request();

    if (statuses.containsKey(ph.Permission.location)) {
      var locationStatus =
          statuses[ph.Permission.location] ?? ph.PermissionStatus.denied;
      if (locationStatus.isPermanentlyDenied) {
        return AttendanceDataStatus.locationPermissionDeniedForever;
      }
      if (!locationStatus.isGranted) {
        return AttendanceDataStatus.locationPermissionDenied;
      }
    }

    if (statuses.containsKey(ph.Permission.microphone)) {
      var microphoneStatus =
          statuses[ph.Permission.microphone] ?? ph.PermissionStatus.denied;
      if (microphoneStatus.isPermanentlyDenied) {
        return AttendanceDataStatus.microphonePermissionDeniedForever;
      }
      if (!microphoneStatus.isGranted) {
        return AttendanceDataStatus.microphonePermissionDenied;
      }
    }

    return AttendanceDataStatus.success;
  }

  /// Collects location and records audio concurrently.
  /// Handles permissions and service checks internally.
  Future<AttendanceDataResult> collectData({
    Duration recordingDuration = const Duration(seconds: 10),
    String role = "student",
  }) async {
    // --- 1. Check & Request Permissions ---
    final permissionStatus = await checkAndRequestPermissions(role: role);
    if (permissionStatus != AttendanceDataStatus.success) {
      return AttendanceDataResult(
        status: permissionStatus,
        errorMessage: _getPermissionErrorMessage(permissionStatus),
      );
    }

    // --- 2. Check Location Service ---
    // Moved service check inside _getLocationInternal for better flow control
    //debugprint("Permissions granted. Starting data collection...");

    // --- 3. Collect Location and Audio Concurrently ---
    try {
      final results = await Future.wait([
        _getLocationInternal(), // Task 1: Get Location (includes service check)
        _recordAudio(recordingDuration), // Task 2: Record Audio
      ]).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          // Overall timeout for both tasks
          //debugprint("Data collection (location+audio) timed out.");
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
        //debugprint("Location collection failed: ${locationResult.status}");
        return locationResult; // Return the specific location error result
      }

      // Check audio result
      if (audioResult.status != AttendanceDataStatus.success ||
          audioResult.audioBytes == null) {
        //debugprint("Audio recording failed: ${audioResult.status}");
        return audioResult; // Return the specific audio error result
      }
      if (audioResult.recordingStartTimeMillis == null) {
        //debugprint("Audio recording failed: ${audioResult.status}");
        return audioResult; // Return the specific audio error result
      }

      // --- Success ---
      //debugprint("Location and Audio collected successfully.");
      return AttendanceDataResult(
        status: AttendanceDataStatus.success,
        locationData: locationResult.locationData,
        audioBytes: audioResult.audioBytes,
        recordingStartTimeMillis: audioResult.recordingStartTimeMillis,
      );
    } on TimeoutException {
      return AttendanceDataResult(
        status: AttendanceDataStatus.locationTimeout,
        errorMessage: "Data collection timed out.",
      );
    } catch (e) {
      //debugprint("Unexpected error during data collection: $e");
      return AttendanceDataResult(
        status: AttendanceDataStatus.unknownError,
        errorMessage: "An unexpected error occurred: ${e.toString()}",
      );
    } finally {
      // Ensure recorder is stopped and disposed if still active
      await _disposeRecorder();
    }
  }

  /// Internal helper to get location, including service check and mock detection.
  Future<AttendanceDataResult> _getLocationInternal() async {
    // Check Location Service
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      //debugprint("Location service disabled. Requesting service...");
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        //debugprint("Location service request denied by user.");
        return AttendanceDataResult(
          status: AttendanceDataStatus.locationServiceDisabled,
        );
      }
    }

    // Get Location Data
    //debugprint("Location services OK. Getting location...");
    try {
      await _location.changeSettings(accuracy: LocationAccuracy.high);
      LocationData? locationData;
      try {
        locationData = await _location.getLocation().timeout(
          const Duration(seconds: 15),
          onTimeout:
              () =>
                  throw TimeoutException('Getting accurate location timed out'),
        );
      } on TimeoutException {
        await _location.changeSettings(accuracy: LocationAccuracy.balanced);

        locationData = await _location.getLocation().timeout(
          const Duration(seconds: 20),
          onTimeout:
              () =>
                  throw TimeoutException('Getting balanced location timed out'),
        );
      }

      // --- Mock Location Check ---
      if (locationData.isMock == true) {
        // Check if explicitly true
        //debugprint("Mock location detected!");
        return AttendanceDataResult(
          status: AttendanceDataStatus.locationIsMocked, // Use the new status
          errorMessage:
              'Mock location detected. Attendance marking disallowed.',
        );
      }

      // Log mock status even if false or null for debugging
      //debugprint( "Location fetched: Lat ${locationData.latitude}, Lon ${locationData.longitude}, Mock: ${locationData.isMock}",);
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
      //debugprint("Error getting location: $e");
      return AttendanceDataResult(
        status: AttendanceDataStatus.locationError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Internal helper to record audio.
  /// Internal helper to record audio to a temporary file and return bytes.
  Future<AttendanceDataResult> _recordAudio(Duration duration) async {
    // Create a fresh recorder instance for each call
    final recorder = AudioRecorder();
    int? recordingStartTimeMillis;
    String? tempPath; // To store the temporary file path

    try {
      if (!await recorder.hasPermission()) {
        return AttendanceDataResult(
          status: AttendanceDataStatus.microphonePermissionDenied,
        );
      }

      // --- Get Temporary Directory ---
      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      tempPath = '${tempDir.path}/temp_attendance_audio_$timestamp.wav';
      //debugprint("Audio recording temporary path: $tempPath");
      // --- End Get Temporary Directory ---

      //debugprint("Starting audio recording to file...");
      recordingStartTimeMillis = DateTime.now().millisecondsSinceEpoch;

      // --- Start Recording to File ---
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          autoGain: false,
          noiseSuppress: false,
          echoCancel: false,
          numChannels: 1,
          sampleRate: 48000,
        ), // Config remains the same
        path: tempPath,
      );
      // --- End Start Recording to File ---

      // Check state after starting
      bool isRecording = await recorder.isRecording();
      //debugprint("Audio recorder state after start: isRecording=$isRecording");
      if (!isRecording) {
        // If it failed to start recording immediately
        throw Exception("Recorder failed to enter recording state.");
      }

      // --- Wait for Duration ---
      // Use Future.delayed to wait for the recording duration
      await Future.delayed(duration);

      // --- Stop Recording ---
      //debugprint("Recording duration reached. Stopping recorder...");
      // Stop recording, get the final path (might be null if stopped early/error)
      final String? finalPath = await recorder.stop();
      //debugprint("Recorder stopped. Final path: $finalPath");

      // --- Read Bytes from File ---
      if (finalPath != null) {
        final File audioFile = File(finalPath);
        if (await audioFile.exists()) {
          final Uint8List audioBytes = await audioFile.readAsBytes();
          //debugprint( "Successfully read ${audioBytes.length} bytes from temporary file.",);

          // --- Delete Temporary File ---
          try {
            await audioFile.delete();
            //debugprint("Temporary audio file deleted: $finalPath");
          } catch (e) {
            //debugprint(  "Warning: Failed to delete temporary audio file $finalPath: $e",);
          }
          // --- End Delete Temporary File ---

          // --- Success ---
          return AttendanceDataResult(
            status: AttendanceDataStatus.success,
            audioBytes: audioBytes,
            recordingStartTimeMillis: recordingStartTimeMillis,
          );
        } else {
          //debugprint("Error: Temporary audio file does not exist after recording: $finalPath",);
          return AttendanceDataResult(
            status: AttendanceDataStatus.recordingError,
            errorMessage: "Recorded audio file was not found.",
            recordingStartTimeMillis: recordingStartTimeMillis,
          );
        }
      } else {
        // recorder.stop() returned null, indicating an issue during recording/stopping
        //debugprint("Error: recorder.stop() returned null.");
        return AttendanceDataResult(
          status: AttendanceDataStatus.recordingError,
          errorMessage: "Recording process failed to complete successfully.",
          recordingStartTimeMillis: recordingStartTimeMillis,
        );
      }
    } catch (e) {
      //debugprint("Error during audio recording process: $e");
      // Attempt to clean up the temp file if path exists and error occurred
      if (tempPath != null) {
        try {
          final File tempFile = File(tempPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
            //debugprint("Cleaned up temporary audio file on error: $tempPath");
          }
        } catch (cleanupError) {
          //debugprint("Error during error cleanup (deleting temp file): $cleanupError",);
        }
      }
      return AttendanceDataResult(
        status: AttendanceDataStatus.recordingError,
        errorMessage: "Failed to record audio: ${e.toString()}",
        recordingStartTimeMillis:
            recordingStartTimeMillis, // Include if captured
      );
    } finally {
      // Ensure recorder is disposed
      await _disposeRecorder(recorder);
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
      //debugprint("AudioRecorder disposed.");
    } catch (e) {
      //debugprint("Error disposing recorder: $e");
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


  // final savedPath = await _saveAudioForDebug(dataResult!.audioBytes!);
  // if (savedPath != null && mounted) {
  //   // Show snackbar indicating save location (optional now)
  //   _showSnackbar(
  //     "Debug audio saved. Preparing share...",
  //     isError: false,
  //     backgroundColor: Colors.teal,
  //     duration: Duration(seconds: 2),
  //   );
  // }
  // Future<String?> _saveAudioForDebug(Uint8List audioBytes) async {
  //   if (!kDebugMode) {
  //     // Only run this function in debug mode
  //     return null;
  //   }

  //   Directory? directory;
  //   try {
  //     // Try getting the public Downloads directory first
  //     // Note: Access might be restricted on newer Android versions without specific permissions
  //     // or might return an app-specific directory within Downloads.
  //     if (Platform.isAndroid) {
  //       directory =
  //           await getExternalStorageDirectory(); // Gets primary external storage
  //       // Try to navigate to a common Downloads path if possible (might fail)
  //       String downloadsPath = '${directory?.path}/Download';
  //       directory = Directory(downloadsPath);
  //       // Check if it exists, if not, fall back to the base external path
  //       if (!await directory.exists()) {
  //         directory = await getExternalStorageDirectory();
  //       }
  //     } else if (Platform.isIOS) {
  //       // On iOS, saving to 'Downloads' isn't standard via path_provider.
  //       // Saving to ApplicationDocumentsDirectory is more common and accessible via Files app.
  //       directory = await getApplicationDocumentsDirectory();
  //     }

  //     if (directory == null) {
  //       //debugprint(
  //         "Could not determine suitable directory for saving debug audio.",
  //       );
  //       return null;
  //     }

  //     // Ensure the directory exists (especially the Downloads subdirectory on Android)
  //     if (!await directory.exists()) {
  //       await directory.create(recursive: true);
  //     }

  //     // Create a unique filename
  //     final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
  //     final String fileName = 'attendance_audio_$timestamp.wav';
  //     final String filePath = '${directory.path}/$fileName';

  //     // Write the file
  //     final File audioFile = File(filePath);
  //     await audioFile.writeAsBytes(audioBytes);

  //     //debugprint("Debug audio saved to: $filePath");
  //     return filePath; // Return the path
  //   } catch (e) {
  //     //debugprint("Error saving debug audio: $e");
  //     return null; // Return null on failure
  //   }
  // }


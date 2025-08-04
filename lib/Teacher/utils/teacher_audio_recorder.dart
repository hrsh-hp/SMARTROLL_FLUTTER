import 'dart:async';
import 'package:record/record.dart';

class TeacherAudioRecorder {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _audioStreamSubscription;

  /// Starts recording and returns a stream of audio data chunks.
  /// The underlying package will handle the chunking efficiently.
  Stream<List<int>> startRecording() {
    // Use a StreamController to manage the output stream.
    // This gives us full control.
    final controller = StreamController<List<int>>();

    _audioRecorder
        .startStream(
          const RecordConfig(
            encoder:
                AudioEncoder.pcm16bits, // Use PCM for raw, uncompressed data
            sampleRate: 16000, // 16kHz is standard for voice
            numChannels: 1,
          ),
        )
        .then((stream) {
          // When the stream from the 'record' package is ready,
          // listen to it and forward the data to our own controller.
          _audioStreamSubscription = stream.listen((data) {
            // Check if the controller is still open before adding data
            if (!controller.isClosed) {
              controller.add(data);
            }
          });
        })
        .catchError((error) {
          // Handle any errors during stream startup
          controller.addError(error);
          controller.close();
        });

    // When the listener of our stream cancels, we clean up.
    controller.onCancel = () {
      stopRecording();
      controller.close();
    };

    return controller.stream;
  }

  /// Stops the recording and cleans up all resources.
  Future<void> stopRecording() async {
    // Cancel the subscription to the audio stream
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    // Stop the recorder if it's still active
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }

    // Dispose of the recorder instance to release hardware resources
    await _audioRecorder.dispose();
  }
}

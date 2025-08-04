// lib/Teacher/Utils/teacher_audio_recorder.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// A utility class to record audio from the microphone and provide a stream
/// of WAV-formatted audio chunks.
class TeacherAudioRecorder {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _audioStreamSubscription;

  // Standard audio configuration for voice.
  static const _sampleRate = 16000;
  static const _numChannels = 1;
  static const _bitDepth = 16;

  static const int _bytesPerSecond =
      _sampleRate * _numChannels * (_bitDepth ~/ 8);

  /// Starts recording and returns a stream of WAV audio data chunks.
  /// Each item in the stream is a complete WAV file in bytes.
  Stream<Uint8List> startRecording() {
    final controller = StreamController<Uint8List>();
    final List<int> buffer = []; // temporary buffer to aggregate chunks

    _audioRecorder
        .startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits, // Raw PCM data is most efficient
            sampleRate: _sampleRate,
            numChannels: _numChannels,
          ),
        )
        .then((stream) {
          // Listen to the raw audio stream from the microphone
          _audioStreamSubscription = stream.listen((data) {
            buffer.addAll(data);
            // Process the buffer as long as it contains at least one full second of audio
            while (buffer.length >= _bytesPerSecond) {
              // Slice off exactly one second's worth of data from the start of the buffer
              final chunkToSend = buffer.sublist(0, _bytesPerSecond);

              // Remove the sliced data from the buffer
              buffer.removeRange(0, _bytesPerSecond);

              // Create the WAV blob and add it to our output stream
              if (!controller.isClosed) {
                controller.add(_createWavBlob(chunkToSend));
              }
            }
          });
        })
        .catchError((error) {
          debugPrint("Error starting audio stream: $error");
          controller.addError(error);
          controller.close();
        });

    // When the UI is done listening, this ensures we clean up resources.
    controller.onCancel = () {
      stopRecording();
      controller.close();
    };

    return controller.stream;
  }

  /// Stops the recording and releases all hardware and software resources.
  Future<void> stopRecording() async {
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
    await _audioRecorder.dispose();
    debugPrint("TeacherAudioRecorder stopped and disposed.");
  }

  /// Creates a WAV file blob (a 44-byte header + raw PCM data) in memory.
  Uint8List _createWavBlob(List<int> pcmData) {
    final int pcmDataLength = pcmData.length;
    final ByteData header = ByteData(44);

    // RIFF chunk
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, 36 + pcmDataLength, Endian.little); // ChunkSize
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6d); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, _numChannels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(
      28,
      _sampleRate * _numChannels * (_bitDepth ~/ 8),
      Endian.little,
    ); // ByteRate
    header.setUint16(
      32,
      _numChannels * (_bitDepth ~/ 8),
      Endian.little,
    ); // BlockAlign
    header.setUint16(34, _bitDepth, Endian.little);

    // data sub-chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, pcmDataLength, Endian.little); // Subchunk2Size

    // Combine header and PCM data into a single byte list
    return Uint8List.fromList(header.buffer.asUint8List() + pcmData);
  }
}

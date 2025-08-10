import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:smartroll/Common/utils/constants.dart';

/// Lightweight queue to persist auto-mark payloads (location + audio) when
/// network is slow/unavailable and retry later.
class PendingQueueService {
  PendingQueueService._();
  static final PendingQueueService instance = PendingQueueService._();

  static const _queueFileName = 'pending_auto_marks.json';
  static const _audioDirName = 'pending_audio';

  Future<Directory> _appDir() async => await getApplicationDocumentsDirectory();

  Future<File> _queueFile() async {
    final dir = await _appDir();
    return File('${dir.path}/$_queueFileName');
  }

  Future<Directory> _audioDir() async {
    final dir = await _appDir();
    final audioDir = Directory('${dir.path}/$_audioDirName');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    try {
      debugPrint('[PendingQueue] Reading queue file...');
      final file = await _queueFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is List) {
        debugPrint('[PendingQueue] Read queue with ${data.length} items');
        return data.cast<Map<String, dynamic>>();
      }
      debugPrint('[PendingQueue] Queue content not a List, resetting to empty');
      return [];
    } catch (e) {
      debugPrint('[PendingQueue] Failed to read queue: $e');
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> items) async {
    final file = await _queueFile();
    await file.writeAsString(jsonEncode(items));
    debugPrint('[PendingQueue] Wrote queue with ${items.length} items');
  }

  /// Enqueue a pending auto mark by saving the audio to a file and metadata to JSON queue.
  Future<void> enqueueAutoMark({
    required String lectureSlug,
    required String deviceIdEncoded,
    required double latitude,
    required double longitude,
    required int recordingStartTimeMillis,
    required Uint8List audioBytes,
  }) async {
    // Cap queue size to avoid unbounded growth
    const maxItems = 10;
    debugPrint('[PendingQueue] Enqueue requested for lecture=$lectureSlug');
    final items = await _readQueue();
    if (items.length >= maxItems) {
      debugPrint(
        '[PendingQueue] Queue at capacity ($maxItems); dropping oldest',
      );
      items.removeAt(0);
    }

    final audioDir = await _audioDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeSlug = lectureSlug.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final audioPath = '${audioDir.path}/audio_${ts}_$safeSlug.wav';
    await File(audioPath).writeAsBytes(audioBytes, flush: true);
    debugPrint(
      '[PendingQueue] Saved audio to $audioPath (${audioBytes.length} bytes)',
    );

    items.add({
      'lectureSlug': lectureSlug,
      'deviceIdEncoded': deviceIdEncoded,
      'latitude': latitude,
      'longitude': longitude,
      'recordingStartTimeMillis': recordingStartTimeMillis,
      'audioPath': audioPath,
      'createdAt': ts,
      'retryCount': 0,
    });

    await _writeQueue(items);
    debugPrint('[PendingQueue] Enqueued item for lecture=$lectureSlug');
  }

  /// Attempts to process queued items if the device is connected.
  /// Returns the number of successfully uploaded items.
  Future<int> processPendingIfConnected({
    required Future<String?> Function() getAccessToken,
    required Future<bool> Function() refreshTokens,
  }) async {
    final conn = await Connectivity().checkConnectivity();
    debugPrint('[PendingQueue] Connectivity status: $conn');
    if (!conn.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    )) {
      debugPrint('[PendingQueue] Not connected; skipping processing');
      return 0;
    }
    return await _processQueue(
      getAccessToken: getAccessToken,
      refreshTokens: refreshTokens,
    );
  }

  Future<int> _processQueue({
    required Future<String?> Function() getAccessToken,
    required Future<bool> Function() refreshTokens,
  }) async {
    var items = await _readQueue();
    if (items.isEmpty) {
      debugPrint('[PendingQueue] No items to process');
      return 0;
    }

    int successCount = 0;
    final updated = <Map<String, dynamic>>[];

    // Get an initial token
    String? token = await getAccessToken();
    if (token == null || token.isEmpty) {
      final refreshed = await refreshTokens();
      if (refreshed) {
        token = await getAccessToken();
      }
    }
    debugPrint(
      '[PendingQueue] Starting processing of ${items.length} items; tokenPresent=${token != null && token.isNotEmpty}',
    );

    for (final item in items) {
      final String? audioPath = item['audioPath'] as String?;
      try {
        final file = audioPath != null ? File(audioPath) : null;
        if (file == null || !await file.exists()) {
          // Drop if audio missing
          debugPrint(
            '[PendingQueue] Missing audio file; dropping item: $audioPath',
          );
          continue;
        }

        // Ensure token present (refresh if needed between items)
        if (token == null || token.isEmpty) {
          final refreshed = await refreshTokens();
          if (refreshed) token = await getAccessToken();
          if (token == null || token.isEmpty) {
            // Keep item for later
            debugPrint('[PendingQueue] No token; keeping item for later');
            updated.add(item);
            continue;
          }
        }

        debugPrint(
          '[PendingQueue] Uploading queued item: lecture=${item['lectureSlug']} file=$audioPath',
        );
        final req = http.MultipartRequest(
          'POST',
          Uri.parse(
            '$backendBaseUrl/api/manage/session/mark_attendance_for_student/',
          ),
        );
        req.headers['Authorization'] = 'Bearer $token';
        req.fields['device_id'] = item['deviceIdEncoded'] as String;
        req.fields['latitude'] = (item['latitude']).toString();
        req.fields['longitude'] = (item['longitude']).toString();
        req.fields['lecture_slug'] = item['lectureSlug'] as String;
        req.fields['start_time'] =
            (item['recordingStartTimeMillis']).toString();
        req.files.add(
          await http.MultipartFile.fromPath(
            'audio',
            audioPath!,
            filename: 'attendance_audio.wav',
          ),
        );

        final streamed = await req.send();
        final resp = await http.Response.fromStream(streamed);
        debugPrint('[PendingQueue] Upload response status=${resp.statusCode}');
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          // Success — clean up file
          try {
            await file.delete();
          } catch (_) {}
          debugPrint('[PendingQueue] Uploaded and deleted $audioPath');
          successCount++;
        } else if (resp.statusCode == 401 || resp.statusCode == 403) {
          // Try refresh once for this item
          debugPrint('[PendingQueue] Unauthorized; attempting token refresh');
          final refreshed = await refreshTokens();
          if (refreshed) {
            token = await getAccessToken();
            if (token != null && token.isNotEmpty) {
              // retry once
              req.headers['Authorization'] = 'Bearer $token';
              final retried = await req.send();
              final retriedResp = await http.Response.fromStream(retried);
              debugPrint(
                '[PendingQueue] Retry response status=${retriedResp.statusCode}',
              );
              if (retriedResp.statusCode == 200 ||
                  retriedResp.statusCode == 201) {
                try {
                  await file.delete();
                } catch (_) {}
                debugPrint(
                  '[PendingQueue] Retry succeeded; deleted $audioPath',
                );
                successCount++;
                continue;
              }
            }
          }
          // Keep item for later if still unauthorized
          debugPrint(
            '[PendingQueue] Still unauthorized; keeping item for later',
          );
          updated.add(item);
        } else {
          // Server error (e.g., 5xx). Increment retryCount and keep/drop accordingly.
          final current = (item['retryCount'] as int?) ?? 0;
          final next = current + 1;
          const maxRetries = 3;
          if (next >= maxRetries) {
            debugPrint(
              '[PendingQueue] Server error ${resp.statusCode}; max retries reached ($maxRetries). Dropping and deleting $audioPath',
            );
            try {
              await file.delete();
            } catch (_) {}
            // Do not re-add; drop from queue
          } else {
            debugPrint(
              '[PendingQueue] Server error ${resp.statusCode}; will retry later (retryCount=$next)',
            );
            final updatedItem = Map<String, dynamic>.from(item);
            updatedItem['retryCount'] = next;
            updated.add(updatedItem);
          }
        }
      } catch (e) {
        // Keep for later on any exception
        final current = (item['retryCount'] as int?) ?? 0;
        final next = current + 1;
        const maxRetries = 3;
        if (next >= maxRetries) {
          debugPrint(
            '[PendingQueue] Exception uploading item (retry maxed). Dropping $audioPath. Error: $e',
          );
          if (audioPath != null) {
            try {
              await File(audioPath).delete();
            } catch (_) {}
          }
          // Drop from queue
        } else {
          debugPrint(
            '[PendingQueue] Exception uploading item: $e; will retry later (retryCount=$next)',
          );
          final updatedItem = Map<String, dynamic>.from(item);
          updatedItem['retryCount'] = next;
          updated.add(updatedItem);
        }
      }
    }

    await _writeQueue(updated);
    debugPrint(
      '[PendingQueue] Processing done; success=$successCount, remaining=${updated.length}',
    );
    return successCount;
  }
}

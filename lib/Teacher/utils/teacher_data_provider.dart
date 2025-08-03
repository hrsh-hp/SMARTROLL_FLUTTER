// lib/Teacher/utils/teacher_data_provider.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:smartroll/Common/utils/constants.dart';

class TeacherDataProvider {
  static Future<List<Map<String, dynamic>>> getClassrooms() async {
    final String? token = await secureStorage.read(key: 'accessToken');
    if (token == null) {
      return [];
    }

    final url =
        Uri.parse('$backendBaseUrl/api/manage/get_classrooms_for_teacher');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);
        if (decodedBody['error'] == false && decodedBody['data'] is List) {
          List<Map<String, dynamic>> classrooms =
              List<Map<String, dynamic>>.from(decodedBody['data']);
                    return classrooms;
        }
      }
    } catch (e) {
      // Handle error
    }
    return [];
  }
}
// lib/services/medace_api.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class MedAceApiService {
  static String get baseUrl {
    if (kReleaseMode) {
      return 'https://omairs-g-14.tail7c5f73.ts.net';
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'https://omairs-g-14.tail7c5f73.ts.net';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'http://127.0.0.1:8000';
    }
    return 'https://omairs-g-14.tail7c5f73.ts.net';
  }

  static String get askUrl => '$baseUrl/ask';
  static String get uploadUrl => '$baseUrl/upload';
  static String get clearSessionUrl => '$baseUrl/clear-session';

  // --- Ask a question (with optional session ID for uploaded docs) ---
  static Future<Map<String, dynamic>?> askQuestion(
      String userQuestion, String selectedModel,
      {String? sessionId}) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(askUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': userQuestion,
          'model': selectedModel,
          'session_id': sessionId,
        }),
      ).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Request timed out after 5 minutes');
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Server error: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Network error: $e");
      return null;
    } finally {
      client.close();
    }
  }

  // --- Upload a PDF and get/update a session ID ---
  static Future<Map<String, dynamic>?> uploadDocument(
      String filePath, String fileName,
      {String? sessionId}) async {
    final client = http.Client();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));

      // Attach the file
      if (kIsWeb) {
        // On web, filePath is actually the bytes as a base64 string
        // (handled separately in main.dart using file picker bytes)
        throw Exception('Use uploadDocumentBytes for web');
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: MediaType('application', 'pdf'),
        ));
      }

      if (sessionId != null) {
        request.fields['session_id'] = sessionId;
      }

      final streamed = await client.send(request).timeout(const Duration(minutes: 2));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Upload error: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Upload network error: $e");
      return null;
    } finally {
      client.close();
    }
  }

  // --- Upload PDF from bytes (for web/mobile file picker) ---
  static Future<Map<String, dynamic>?> uploadDocumentBytes(
      List<int> bytes, String fileName,
      {String? sessionId}) async {
    final client = http.Client();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType('application', 'pdf'),
      ));

      if (sessionId != null) {
        request.fields['session_id'] = sessionId;
      }

      final streamed = await client.send(request).timeout(const Duration(minutes: 2));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Upload error: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Upload network error: $e");
      return null;
    } finally {
      client.close();
    }
  }

  // --- Clear all uploaded documents for a session ---
  static Future<bool> clearSession(String sessionId) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(clearSessionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print("Clear session error: $e");
      return false;
    } finally {
      client.close();
    }
  }
}
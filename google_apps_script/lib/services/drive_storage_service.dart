import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Spark-compatible media bridge backed by Google Drive through a secure
/// Google Apps Script endpoint. The Flutter app never contains Drive
/// credentials; it sends the Firebase ID token and the bridge authorizes the
/// request before touching Drive.
class DriveStorageService {
  static const String endpoint = String.fromEnvironment(
    'CDH_DRIVE_BACKEND_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzMvodYlFaFeFEfPCYoWeZyA9hXWM7rm_r3O2Bp7sAQwKMZprQabvfML7zAmBXhItOHvA/exec',
  );

  static Uri _uri() {
    final value = endpoint.trim();
    if (value.isEmpty) {
      throw StateError(
        'Google Drive backend is not configured. Build with --dart-define=CDH_DRIVE_BACKEND_URL=<your Apps Script URL>.',
      );
    }
    return Uri.parse(value);
  }

  static Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Authentication required.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw StateError('Could not obtain Firebase authentication token.');
    return token;
  }

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final response = await http.post(
      _uri(),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) decoded = Map<String, dynamic>.from(raw);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
      throw StateError((decoded['error'] ?? 'Google Drive backend request failed (${response.statusCode}).').toString());
    }
    return decoded;
  }

  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String scope,
    String? ownerUid,
  }) async {
    if (bytes.isEmpty) throw StateError('Cannot upload an empty file.');
    final token = await _token();
    final result = await _post({
      'action': 'upload',
      'idToken': token,
      'fileName': fileName,
      'contentType': contentType,
      'scope': scope,
      'ownerUid': ownerUid ?? FirebaseAuth.instance.currentUser!.uid,
      'dataBase64': base64Encode(bytes),
    });
    return (result['fileRef'] ?? '').toString();
  }

  static Future<Uint8List> downloadBytes(String fileRef) async {
    final id = fileRef.startsWith('drive://') ? fileRef.substring(8) : fileRef;
    if (id.trim().isEmpty) throw StateError('Google Drive file reference is empty.');
    final token = await _token();
    final result = await _post({'action': 'download', 'idToken': token, 'fileId': id.trim()});
    final encoded = (result['dataBase64'] ?? '').toString();
    if (encoded.isEmpty) throw StateError('Google Drive returned an empty file.');
    return base64Decode(encoded);
  }

  static Future<String> getPrivateFileUrl(String fileRef) async {
    final id = fileRef.startsWith('drive://') ? fileRef.substring(8) : fileRef;
    if (id.trim().isEmpty) throw StateError('Google Drive file reference is empty.');
    final token = await _token();
    final result = await _post({'action': 'signedUrl', 'idToken': token, 'fileId': id.trim()});
    return (result['url'] ?? '').toString();
  }
}

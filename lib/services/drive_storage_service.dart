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

    // Google Apps Script ContentService commonly returns a 302 redirect to
    // a temporary googleusercontent.com URL. Native clients usually follow
    // this automatically, but Flutter Web can expose the intermediate 302.
    // If that happens, follow the one-time GET target ourselves.
    http.Response effectiveResponse = response;
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final redirect = response.headers['location'];
      if (redirect != null && redirect.trim().isNotEmpty) {
        effectiveResponse = await http.get(Uri.parse(redirect));
      }
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(effectiveResponse.body);
      if (raw is Map) decoded = Map<String, dynamic>.from(raw);
    } catch (_) {}

    final success = decoded['ok'] == true || decoded['success'] == true;
    if (effectiveResponse.statusCode < 200 || effectiveResponse.statusCode >= 300 || !success) {
      final backendError = (decoded['error'] ?? decoded['message'] ?? '').toString().trim();
      throw StateError(backendError.isNotEmpty
          ? backendError
          : 'Google Drive backend request failed (${effectiveResponse.statusCode}).');
    }
    return decoded;
  }


  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is String || value is num || value is bool) return value;
    if (value is DateTime) return value.toIso8601String();
    try {
      final dynamic milliseconds = value.millisecondsSinceEpoch;
      if (milliseconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt()).toIso8601String();
      }
    } catch (_) {}
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), _jsonSafe(val)));
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }

  static Future<String> archiveJsonRecord({
    required String scope,
    required String recordId,
    required String ownerUid,
    required Map<String, dynamic> data,
  }) async {
    final token = await _token();
    final result = await _post({
      'action': 'archiveRecord',
      'idToken': token,
      'scope': scope,
      'recordId': recordId,
      'ownerUid': ownerUid,
      'actorUid': FirebaseAuth.instance.currentUser!.uid,
      'data': _jsonSafe(data),
    });
    return (result['fileRef'] ?? '').toString();
  }

  static Future<void> deleteArchivedRecord({
    required String scope,
    required String recordId,
    required String ownerUid,
  }) async {
    final token = await _token();
    await _post({
      'action': 'deleteArchivedRecord',
      'idToken': token,
      'scope': scope,
      'recordId': recordId,
      'ownerUid': ownerUid,
      'actorUid': FirebaseAuth.instance.currentUser!.uid,
    });
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

  static String _normalizeDriveFileId(String fileRef) {
    var id = fileRef.trim();
    // Older chat messages were saved as drive://drive://<id> because the
    // upload service already returns the canonical drive:// reference and
    // the chat layer added a second prefix. Normalize both old and new
    // records so existing screenshots remain readable.
    while (id.toLowerCase().startsWith('drive://')) {
      id = id.substring(8).trim();
    }
    return id;
  }

  static Future<String> uploadAdminTutorialVideo({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String language,
  }) async {
    if (bytes.isEmpty) throw StateError('Cannot upload an empty video.');
    final token = await _token();
    final result = await _post({
      'action': 'uploadHowToUseAppVideo',
      'idToken': token,
      'language': language,
      'fileName': fileName,
      'contentType': contentType,
      'dataBase64': base64Encode(bytes),
    });
    final ref = (result['fileRef'] ?? '').toString().trim();
    if (ref.isEmpty) throw StateError('Backend did not return a tutorial video reference.');
    return ref;
  }

  static Future<Uint8List> downloadBytes(String fileRef) async {
    final id = _normalizeDriveFileId(fileRef);
    if (id.isEmpty) throw StateError('Google Drive file reference is empty.');
    final token = await _token();
    final result = await _post({'action': 'download', 'idToken': token, 'fileId': id});
    final encoded = (result['dataBase64'] ?? '').toString();
    if (encoded.isEmpty) throw StateError('Google Drive returned an empty file.');
    try {
      return base64Decode(encoded);
    } catch (_) {
      throw StateError('Google Drive returned invalid image data.');
    }
  }

  static Future<String> getPrivateFileUrl(String fileRef) async {
    final id = _normalizeDriveFileId(fileRef);
    if (id.isEmpty) throw StateError('Google Drive file reference is empty.');
    final token = await _token();
    final result = await _post({'action': 'signedUrl', 'idToken': token, 'fileId': id});
    return (result['url'] ?? '').toString();
  }
}

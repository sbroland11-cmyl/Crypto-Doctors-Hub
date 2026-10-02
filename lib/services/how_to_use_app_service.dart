import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'drive_storage_service.dart';

class HowToUseAppService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DocumentReference<Map<String, dynamic>> get _config => _db.collection('howToUseApp').doc('config');

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchConfig() => _config.snapshots();

  static Map<String, dynamic>? videoEntry(Map<String, dynamic> data, String language) {
    final raw = data[language];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static Future<String> uploadVideo({
    required String language,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    if (language != 'english' && language != 'urdu') {
      throw ArgumentError('Unsupported tutorial language.');
    }
    final ref = await DriveStorageService.uploadAdminTutorialVideo(
      bytes: bytes,
      fileName: 'cdh_how_to_use_${language}_${DateTime.now().millisecondsSinceEpoch}_$fileName',
      contentType: contentType,
      language: language,
    );
    await _config.set({
      language: {
        'fileRef': ref,
        'fileName': fileName,
        'contentType': contentType,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
    return ref;
  }
}

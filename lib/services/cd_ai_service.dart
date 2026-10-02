import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class CDAiService {
  static const String backendUrl = 'https://script.google.com/macros/s/AKfycbzMvodYlFaFeFEfPCYoWeZyA9hXWM7rm_r3O2Bp7sAQwKMZprQabvfML7zAmBXhItOHvA/exec';
  static Future<String> ask({required String question, required bool isAdmin}) async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null) throw StateError('Authentication required.');
    final token=await user.getIdToken();
    final response=await http.post(Uri.parse(backendUrl),headers:{'Content-Type':'application/json'},body:jsonEncode({'action':'cd_ai_ask','idToken':token,'question':question}));
    if(response.statusCode<200||response.statusCode>=300) throw StateError('AI backend unavailable.');
    final data=jsonDecode(response.body) as Map<String,dynamic>;
    if(data['success']!=true) throw StateError((data['message']??'AI request failed.').toString());
    return (data['answer']??'').toString();
  }
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';

class NotificationService {
  static const _vapidKey = 'BBywmF1p6_aBOBE6noheR_mTujRs97F7PHOJYrcMJR3oHT0Q2J5iBOQayWwj6Nb2_Ov7ig-grBeStH1LYGwPb54';

  static Future<void> init() async {
    try {
      print('🔔 NotificationService init started');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final token = await _getFCMToken();
      if (token != null) {
        print('🔔 Token: $token');
        await _saveToken(token);
        print('🔔 Token saved!');
      }
    } catch (e) {
      print('❌ Notification init error: $e');
    }
  }

  static Future<String?> _getFCMToken() async {
    try {
      if (kIsWeb) {
        return await FirebaseMessaging.instance.getToken(
          vapidKey: _vapidKey,
        );
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      print('❌ Get FCM token error: $e');
      return null;
    }
  }

  static Future<void> _saveToken(String token) async {
    await Supabase.instance.client
        .from('admin_tokens')
        .upsert({'token': token});
  }
}
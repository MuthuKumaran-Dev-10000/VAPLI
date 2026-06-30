import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FcmSubscriptionHelper {
  static Future<void> handleFcmTopicSubscription(String dbKey) async {
    try {
      final fcm = FirebaseMessaging.instance;
      
      // Request permission (standard practice for notifications)
      await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Sanitize topic name: only alphanumeric, dash, underscore, dot, percent, tilde are allowed in FCM topics
      final topicName = dbKey.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');

      final prefs = await SharedPreferences.getInstance();
      final oldTopic = prefs.getString('subscribed_fcm_topic');
      
      if (oldTopic != null && oldTopic != topicName) {
        await fcm.unsubscribeFromTopic(oldTopic);
        debugPrint('[FCM] Unsubscribed from old topic: $oldTopic');
      }
      
      await fcm.subscribeToTopic(topicName);
      await prefs.setString('subscribed_fcm_topic', topicName);
      debugPrint('[FCM] Subscribed to client topic: $topicName');
    } catch (e) {
      debugPrint('[FCM ERROR] Failed to handle topic subscription: $e');
    }
  }
}

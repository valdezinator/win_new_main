import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDcAFT1IRCKKd0Rn8mTiNyZtGG6BjD0WMc",
    authDomain: "cresca-main.firebaseapp.com",
    projectId: "cresca-main",
    storageBucket: "cresca-main.firebasestorage.app",
    messagingSenderId: "640418033387",
    appId: "1:640418033387:web:3eae2775473b5302b618ae",
    measurementId: "G-0SNDE8H637"
  );


  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXx',
    appId: '1:640418033387:web:bbd77baf0e5eb41ab618ae',
    messagingSenderId: '640418033387',
    projectId: 'cresca-main',
    storageBucket: 'cresca-main.appspot.com',
  );
}

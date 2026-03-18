import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return android; // Fallback to Android config for non-mobile platforms
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return android; // Update with iOS config when available
      case TargetPlatform.windows:
        return android;
      case TargetPlatform.linux:
        return android;
      case TargetPlatform.macOS:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA1WNWlIMLpwmb5T7b-XEjIBBq7kMM1vCw',
    appId: '1:538999544234:android:4f7aab266c60d10f62b3d3',
    messagingSenderId: '538999544234',
    projectId: 'fall-detection-61bca',
    storageBucket: 'fall-detection-61bca.firebasestorage.app',
  );
}

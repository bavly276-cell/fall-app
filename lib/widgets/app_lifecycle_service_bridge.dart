import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/background_service.dart';

/// Starts the Android foreground monitoring service when the app goes to the
/// background, and stops it when the app returns to foreground.
///
/// This helps avoid having both the UI isolate and the background isolate
/// fighting over the BLE connection at the same time.
class AppLifecycleServiceBridge extends StatefulWidget {
  final Widget child;

  const AppLifecycleServiceBridge({super.key, required this.child});

  @override
  State<AppLifecycleServiceBridge> createState() =>
      _AppLifecycleServiceBridgeState();
}

class _AppLifecycleServiceBridgeState extends State<AppLifecycleServiceBridge>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Avoid doing anything on web.
    if (kIsWeb) return;

    // Best-effort, fire-and-forget.
    //
    // Important: when Android shows a runtime permission dialog the app often
    // transitions to `inactive`. Starting the background isolate/service at that
    // moment can race with the permission flow and crash/close the app.
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(BackgroundMonitorService.stop());
        break;
      case AppLifecycleState.inactive:
        // Do nothing on inactive to avoid fighting with permission dialogs.
        break;
      case AppLifecycleState.paused:
        unawaited(BackgroundMonitorService.start());
        break;
      case AppLifecycleState.hidden:
        // Not available on all platforms; treat like paused.
        unawaited(BackgroundMonitorService.start());
        break;
      case AppLifecycleState.detached:
        // App is terminating; don't spin up a background service here.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

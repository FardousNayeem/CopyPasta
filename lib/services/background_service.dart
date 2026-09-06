import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The foreground service's own isolate entry point.
///
/// It does nothing on purpose. The HTTP server lives in the main isolate; all
/// this service is for is holding a foreground notification so Android leaves
/// the process alone while the app is not on screen.
@pragma('vm:entry-point')
void startBackgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

enum BackgroundEnableResult {
  started,
  notSupported,
  notificationDenied,
  notificationPermanentlyDenied,
  failed,
}

/// Keeps CopyPasta serving while it is in the background.
///
/// **What this does and does not buy you.** With the service running, sending
/// the app to the background, locking the screen or switching apps no longer
/// stops the LAN server, because Android will not reclaim a process that holds
/// a foreground service. Swiping CopyPasta out of the recents list still stops
/// it: that destroys the activity and the isolate the server runs in, so the
/// service is configured to stop with the task rather than leave a notification
/// standing for a server that is gone.
class BackgroundService extends ChangeNotifier {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  static const _prefsEnabled = 'background_keep_alive';
  static const _channelId = 'copypasta_sharing';
  static const _serviceId = 43210;

  bool _enabled = false;
  bool _running = false;
  String? lastError;

  bool get isEnabled => _enabled;
  bool get isRunning => _running;

  /// Android only. The desktops never kill a running process, and iOS gives no
  /// equivalent guarantee to hold on to.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!isSupported) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Sharing over Wi-Fi',
        channelDescription:
            'Shown while CopyPasta stays reachable from your other devices.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Nothing to do on a timer. The service exists to hold the process.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        // Keeps the Wi-Fi radio associated while the screen is off, which is
        // the whole point: an unreachable device shares nothing.
        allowWifiLock: true,
        // The server dies with the activity, so the notification must not
        // outlive it and promise something untrue.
        stopWithTask: true,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsEnabled) ?? false;
    _running = await FlutterForegroundTask.isRunningService;

    if (_enabled && !_running) {
      await enable(persist: false);
    }
    notifyListeners();
  }

  Future<BackgroundEnableResult> enable({
    bool persist = true,
    String? detail,
  }) async {
    if (!isSupported) return BackgroundEnableResult.notSupported;

    // Android 13 and later will not show the service notification without
    // this, and a foreground service with no visible notification is exactly
    // what the platform refuses to run.
    var permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      permission = await FlutterForegroundTask.requestNotificationPermission();
    }
    if (permission == NotificationPermission.permanently_denied) {
      return BackgroundEnableResult.notificationPermanentlyDenied;
    }
    if (permission != NotificationPermission.granted) {
      return BackgroundEnableResult.notificationDenied;
    }

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await _update(detail);
      } else {
        final result = await FlutterForegroundTask.startService(
          serviceId: _serviceId,
          serviceTypes: const [ForegroundServiceTypes.dataSync],
          notificationTitle: 'CopyPasta is sharing',
          notificationText: detail ?? 'Reachable from your other devices',
          callback: startBackgroundCallback,
        );
        if (result is ServiceRequestFailure) {
          lastError = result.error.toString();
          notifyListeners();
          return BackgroundEnableResult.failed;
        }
      }
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return BackgroundEnableResult.failed;
    }

    lastError = null;
    _running = true;
    _enabled = true;
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsEnabled, true);
    }
    notifyListeners();
    return BackgroundEnableResult.started;
  }

  Future<void> disable() async {
    _enabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, false);

    if (isSupported) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        lastError = e.toString();
      }
    }
    _running = false;
    notifyListeners();
  }

  /// Puts the current address in the notification, so the line the user needs
  /// to type into a browser is on the lock screen rather than three taps deep.
  Future<void> describe(String detail) async {
    if (!isSupported || !_running) return;
    await _update(detail);
  }

  Future<void> _update(String? detail) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'CopyPasta is sharing',
        notificationText: detail ?? 'Reachable from your other devices',
      );
    } catch (_) {
      // A notification that failed to update is not worth surfacing; the
      // service itself is still running.
    }
  }
}

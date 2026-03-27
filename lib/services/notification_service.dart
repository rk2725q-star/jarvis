import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/widgets.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_reply_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.handleNotificationReply(response);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // Force Tamil Nadu Time (IST)

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: NotificationService.handleNotificationReply,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final NotificationAppLaunchDetails? launchDetails = 
        await _flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      if (launchDetails.notificationResponse != null) {
        NotificationService.handleNotificationReply(launchDetails.notificationResponse!);
      }
    }

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
        
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();

    _isInitialized = true;

    await _scheduleDailyRoutines();
    await _scheduleReports();
  }

  static Future<void> handleNotificationReply(NotificationResponse response) async {
    debugPrint('[NotifReply] actionId=${response.actionId}, input=${response.input}');
    final prefs = await SharedPreferences.getInstance();

    if (response.actionId == 'reply_action') {
      final userReply = response.input?.trim() ?? '';
      if (userReply.isEmpty) return;

      final history = prefs.getStringList('jarvis_memory_history') ?? [];
      history.add('USER REPLIED TO NOTIFICATION ("${response.payload ?? "Reminder"}"): "$userReply"');
      await prefs.setStringList('jarvis_memory_history', history);

      final notifId = response.id ?? 999;
      final localPlugin = FlutterLocalNotificationsPlugin();
      const replyChannel = NotificationDetails(
        android: AndroidNotificationDetails(
          'jarvis_reply_channel',
          'JARVIS Direct Replies',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        ),
      );

      await localPlugin.show(
        id: notifId,
        title: 'JARVIS',
        body: '💭 Thinking...',
        notificationDetails: replyChannel,
      );

      final aiReply = await NotificationReplyService.generateReply(
        userReply, 
        response.payload ?? 'JARVIS Reminder',
      );

      await localPlugin.show(
        id: notifId,
        title: 'JARVIS 💬',
        body: aiReply,
        notificationDetails: replyChannel,
      );
    } else {
      await prefs.setString('pending_notification_reply', response.payload ?? 'Reminder');
      
      final history = prefs.getStringList('jarvis_memory_history') ?? [];
      history.add('USER OPENED APP FROM NOTIFICATION: "${response.payload ?? "Reminder"}"');
      await prefs.setStringList('jarvis_memory_history', history);
    }
  }

  Future<void> _scheduleDailyRoutines() async {
    final prefs = await SharedPreferences.getInstance();

    // Mapping of routine types to their metadata: (idPrefix, title, body, defaultHour, defaultMin)
    final routineMeta = {
      'morning':   (110, 'Good Morning! 🌅', 'Coffee or tea drink or not?', 6, 0),
      'breakfast': (120, 'Time for Breakfast 🍳', 'Kalai Saptiya?', 9, 30),
      'lunch':     (130, 'Afternoon Check 🍛', 'Madhiyam Saptiya?', 13, 30),
      'evening':   (140, 'Evening Break! ☕', 'Time for your evening tea or coffee?', 18, 0),
      'dinner':    (150, 'Dinner Time 🍽️', 'Night Saptiya?', 20, 0),
      'sleep':     (160, 'Time to Sleep 😴', "It's getting late, consider going to sleep soon.", 22, 0),
    };

    for (var entry in routineMeta.entries) {
      final type = entry.key;
      final meta = entry.value;
      
      for (int i = 1; i <= 7; i++) {
        // Hardcoded generic defaults
        int defH = meta.$4;
        int defM = meta.$5;

        final hour = prefs.getInt('routine_${type}_h_$i') ?? 
                    prefs.getInt('routine_${type}_hour') ?? defH;
        final min  = prefs.getInt('routine_${type}_m_$i') ?? 
                    prefs.getInt('routine_${type}_min') ?? defM;

        await _scheduleWeekly(
          id: meta.$1 + i, 
          title: meta.$2,
          body: meta.$3,
          day: i,
          hour: hour,
          minute: min,
        );
      }
    }
  }


  Future<void> _scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required int day,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    while (scheduledDate.weekday != day || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: title,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'jarvis_routine_channel', 
          'JARVIS Routines',
          channelDescription: 'Weekly recurring routines',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Update a routine time and reschedule all routines
  Future<void> updateRoutine(String type, {int? weekday, required int hour, required int minute}) async {
    final prefs = await SharedPreferences.getInstance();
    if (weekday != null) {
      // If weekday 0 is passed, it means "all weekdays" (1-6)
      if (weekday == 0) {
        for (int i = 1; i <= 6; i++) {
          await prefs.setInt('routine_${type}_h_$i', hour);
          await prefs.setInt('routine_${type}_m_$i', minute);
        }
      } else {
        await prefs.setInt('routine_${type}_h_$weekday', hour);
        await prefs.setInt('routine_${type}_m_$weekday', minute);
      }
    } else {
      await prefs.setInt('routine_${type}_hour', hour);
      await prefs.setInt('routine_${type}_min', minute);
    }
    await _scheduleDailyRoutines();
    debugPrint('[JARVIS] Routine updated: $type (day: $weekday) to $hour:$minute');
  }

  /// Schedule a specific custom reminder
  Future<void> scheduleReminder(int id, String title, String body, DateTime scheduledDate) async {
    final scheduleTz = tz.TZDateTime.from(scheduledDate, tz.local);
    if (scheduleTz.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: title,
      scheduledDate: scheduleTz,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'jarvis_reminder_channel', 
          'JARVIS Reminders',
          channelDescription: 'User requested notifications and reminders',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: const BigTextStyleInformation(''),
          playSound: true,
          enableVibration: true,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'open_action',
              'Open',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    debugPrint('[JARVIS] Reminder scheduled: $title at $scheduleTz');
  }

  Future<void> cancelNotification(int id) async {
    // If it's a base ID, cancel all 7 weekdays
    if (id == 110 || id == 120 || id == 130 || id == 140 || id == 150 || id == 160) {
      for (int i = 1; i <= 7; i++) {
        await _flutterLocalNotificationsPlugin.cancel(id: id + i);
      }
    } else {
      await _flutterLocalNotificationsPlugin.cancel(id: id);
    }
    debugPrint('[JARVIS] Notification cancelled: $id');
  }

  /// Cancels a routine for TODAY only and ensures it is scheduled for NEXT week.
  Future<void> skipRoutineForToday(String type) async {
    final meta = {
      'morning':   110,
      'breakfast': 120,
      'lunch':     130,
      'evening':   140,
      'dinner':    150,
      'sleep':     160,
    };
    final baseId = meta[type];
    if (baseId == null) return;

    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1-7 (Mon-Sun)
    final routineId = baseId + todayWeekday;

    // 1. Cancel today's occurrence
    await _flutterLocalNotificationsPlugin.cancel(id: routineId);
    
    // 2. Re-schedule starting from tomorrow so it picks the NEXT week's occurrence
    final prefs = await SharedPreferences.getInstance();
    int defH = type == 'breakfast' ? 9 : (type == 'lunch' ? 13 : (type == 'dinner' ? 20 : (type == 'sleep' ? 22 : 6)));
    int defM = type == 'breakfast' ? 30 : (type == 'lunch' ? 30 : 0);

    final hour = prefs.getInt('routine_${type}_h_$todayWeekday') ?? 
                prefs.getInt('routine_${type}_hour') ?? defH;
    final min  = prefs.getInt('routine_${type}_m_$todayWeekday') ?? 
                prefs.getInt('routine_${type}_min') ?? defM;

    final tomorrow = tz.TZDateTime.now(tz.local).add(const Duration(days: 1));
    var scheduledDate = tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, hour, min);

    while (scheduledDate.weekday != todayWeekday) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: routineId,
      title: _getRoutineTitle(type),
      body: _getRoutineBody(type),
      payload: _getRoutineTitle(type),
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'jarvis_routine_channel', 
          'JARVIS Routines',
          channelDescription: 'Weekly recurring routines',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
    
    debugPrint('[JARVIS] skipped $type for today. Next scheduled: $scheduledDate');
  }

  String _getRoutineTitle(String type) {
    if (type == 'morning') return 'Good Morning! 🌅';
    if (type == 'breakfast') return 'Time for Breakfast 🍳';
    if (type == 'lunch') return 'Afternoon Check 🍛';
    if (type == 'evening') return 'Evening Break! ☕';
    if (type == 'dinner') return 'Dinner Time 🍽️';
    if (type == 'sleep') return 'Time to Sleep 😴';
    return 'JARVIS Routine';
  }

  String _getRoutineBody(String type) {
    if (type == 'morning') return 'Coffee or tea drink or not?';
    if (type == 'breakfast') return 'Kalai Saptiya?';
    if (type == 'lunch') return 'Madhiyam Saptiya?';
    if (type == 'evening') return 'Time for your evening tea or coffee?';
    if (type == 'dinner') return 'Night Saptiya?';
    if (type == 'sleep') return "It's getting late, consider going to sleep soon.";
    return 'Check-in time!';
  }

  Future<void> _scheduleReports() async {
    await _schedulePeriodic(
      id: 201,
      title: "Weekly Performance Report 📊",
      body: "Tap to see how your week went!",
      day: DateTime.sunday,
      hour: 20,
      match: DateTimeComponents.dayOfWeekAndTime,
    );

    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    await _schedulePeriodic(
      id: 202,
      title: "Monthly Achievement Summary 📅",
      body: "You finished another month! Let's review.",
      day: lastDay,
      hour: 21,
      match: DateTimeComponents.dayOfMonthAndTime,
    );

    await _schedulePeriodic(
      id: 203,
      title: "Year Recap 🎊",
      body: "What a year! See your annual stats.",
      month: 12,
      day: 31,
      hour: 22,
      match: DateTimeComponents.dateAndTime,
    );
  }

  Future<void> _schedulePeriodic({
    required int id,
    required String title,
    required String body,
    int? month,
    int? day,
    required int hour,
    DateTimeComponents match = DateTimeComponents.time,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, month ?? now.month, day ?? now.day, hour, 0);

    if (scheduledDate.isBefore(now)) {
      if (match == DateTimeComponents.dayOfWeekAndTime) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      } else if (match == DateTimeComponents.dayOfMonthAndTime) {
        scheduledDate = tz.TZDateTime(tz.local, now.year, now.month + 1, day!, hour);
      } else if (match == DateTimeComponents.dateAndTime) {
        scheduledDate = tz.TZDateTime(tz.local, now.year + 1, month!, day!, hour);
      } else {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }
    }

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: title,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'jarvis_report_channel',
          'JARVIS Reports',
          channelDescription: 'Weekly, Monthly, and Yearly performance summaries',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: match,
    );
  }

  int? getRoutineIdFromPurpose(String purpose) {
    final lower = purpose.toLowerCase();
    
    if (lower.contains('coffee') || lower.contains('tea') || lower.contains('wake up') || lower.contains('morning')) {
      if (lower.contains('evening') || lower.contains('18:00') || lower.contains('6:00 pm')) return 140;
      return 110;
    }
    if (lower.contains('breakfast') || lower.contains('kalai')) return 120;
    if (lower.contains('lunch') || lower.contains('madhiyam')) return 130;
    if (lower.contains('dinner') || lower.contains('night')) return 150;
    if (lower.contains('sleep')) return 160;

    if (lower.contains('06:00') || lower.contains('6:00 am')) return 110;
    if (lower.contains('09:30') || lower.contains('9:30 am')) return 120;
    if (lower.contains('13:30') || lower.contains('1:30 pm')) return 130;
    if (lower.contains('18:00') || lower.contains('6:00 pm')) return 140;
    if (lower.contains('20:00') || lower.contains('8:00 pm')) return 150;
    if (lower.contains('22:00') || lower.contains('10:00 pm')) return 160;
    
    return null;
  }
}

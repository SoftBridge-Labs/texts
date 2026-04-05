import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:telephony/telephony.dart' as tp;

class NotificationService {
  static const String _channelId = 'sms_channel';
  static const String _channelName = 'SMS Notifications';
  static const String _channelDescription = 'Notifications for incoming SMS messages';

  static const String _otpChannelId = 'otp_channel';
  static const String _otpChannelName = 'OTP Notifications';
  static const String _otpChannelDescription = 'Secure notifications for OTP messages';

  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static void Function(String address)? onNotificationTap;

  static final _otpRegexps = [
    RegExp(r'\b(\d{4,8})\b.*(otp|one.?time|passcode|verification|code|pin)', caseSensitive: false),
    RegExp(r'(otp|one.?time|passcode|verification|code|pin).*\b(\d{4,8})\b', caseSensitive: false),
  ];

  static String? _extractOtp(String body) {
    for (final re in _otpRegexps) {
      final m = re.firstMatch(body);
      if (m != null) {
        for (int i = 1; i <= m.groupCount; i++) {
          final g = m.group(i);
          if (g != null && RegExp(r'^\d{4,8}$').hasMatch(g)) return g;
        }
      }
    }
    return null;
  }

  static bool _isOtp(String body) => _extractOtp(body) != null;

  static Future<void> init({bool requestPermissions = true}) async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(_channelId, _channelName, description: _channelDescription, importance: Importance.high),
    );

    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _otpChannelId, 
        _otpChannelName, 
        description: _otpChannelDescription, 
        importance: Importance.max, 
        enableVibration: true, 
        playSound: true,
        sound: RawResourceAndroidNotificationSound('otp_sms'),
      ),
    );

    if (requestPermissions) {
      await androidImplementation?.requestNotificationsPermission();
    }
    _isInitialized = true;
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty && onNotificationTap != null) {
      onNotificationTap!(payload);
    }
  }

  static Future<void> showSmsNotification(tp.SmsMessage message) async {
    if (!_isInitialized) await init(requestPermissions: false);
    final body = message.body ?? '';
    if (_isOtp(body)) {
      await _showOtpNotification(message, body);
    } else {
      await _showRegularNotification(message, body);
    }
  }

  static Future<void> _showOtpNotification(tp.SmsMessage message, String body) async {
    final otp = _extractOtp(body) ?? '';
    
    // We use a BigPictureStyle-like approach to make the OTP stand out
    // Since we can't easily do custom views in pure Flutter local notifications for the system tray,
    // we use a specific formatting that Android highlights well.
    final String styledTitle = "🔐 YOUR OTP CODE: $otp";
    final String styledBody = "Tap to copy or view message from ${message.address}";

    final AndroidNotificationDetails otpDetails = AndroidNotificationDetails(
      _otpChannelId,
      _otpChannelName,
      channelDescription: _otpChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'OTP Received',
      styleInformation: BigTextStyleInformation(
        "Your verification code is:\n\n$otp\n\nDo not share this code with anyone.",
        contentTitle: styledTitle,
        summaryText: "Secure OTP",
      ),
      visibility: NotificationVisibility.public,
      sound: const RawResourceAndroidNotificationSound('otp_sms'),
      enableVibration: true,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('copy_otp', 'Copy Code', showsUserInterface: true),
      ],
    );

    await _notificationsPlugin.show(
      message.address?.hashCode ?? 0,
      styledTitle,
      styledBody,
      NotificationDetails(android: otpDetails),
      payload: message.address ?? '',
    );
  }

  static Future<void> _showRegularNotification(tp.SmsMessage message, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
    );
    await _notificationsPlugin.show(
      message.address?.hashCode ?? 0,
      message.address ?? 'Unknown',
      body,
      const NotificationDetails(android: androidPlatformChannelSpecifics),
      payload: message.address ?? '',
    );
  }
}

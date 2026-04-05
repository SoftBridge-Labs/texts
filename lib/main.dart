import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart' as tp;
import 'notification_service.dart';
import 'screens/message_list_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/conversation_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const MethodChannel _platform = MethodChannel('in.softbridgelabs.text/default_sms');

class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  ThemeMode _themeMode = ThemeMode.light;
  double _fontSizeScale = 1.0;
  String _fontSizeName = 'Medium';
  bool _linksEnabled = false;
  
  Set<String> _pinnedAddresses = {};
  Set<String> _blockedAddresses = {};
  // Structure: Folder Name -> { Sender Address -> List of Message IDs }
  Map<String, Map<String, List<int>>> _folders = {}; 

  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;
  String get fontSizeName => _fontSizeName;
  bool get linksEnabled => _linksEnabled;
  Set<String> get pinnedAddresses => _pinnedAddresses;
  Set<String> get blockedAddresses => _blockedAddresses;
  Map<String, Map<String, List<int>>> get folders => _folders;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = (prefs.getBool('dark_mode') ?? false) ? ThemeMode.dark : ThemeMode.light;
    _fontSizeName = prefs.getString('font_size') ?? 'Medium';
    _fontSizeScale = _getScale(_fontSizeName);
    _linksEnabled = prefs.getBool('links_enabled') ?? false;
    
    _pinnedAddresses = (prefs.getStringList('pinned_addresses') ?? []).toSet();
    _blockedAddresses = (prefs.getStringList('blocked_addresses') ?? []).toSet();
    
    final foldersJson = prefs.getString('custom_folders_v3') ?? '{}';
    try {
      final Map<String, dynamic> decoded = json.decode(foldersJson);
      _folders = decoded.map((key, value) {
        final Map<String, dynamic> senders = Map<String, dynamic>.from(value);
        return MapEntry(key, senders.map((sKey, sValue) => MapEntry(sKey, List<int>.from(sValue))));
      });
    } catch (e) {
      _folders = {};
    }
    
    notifyListeners();
  }

  double _getScale(String size) {
    if (size == 'Small') return 0.85;
    if (size == 'Large') return 1.2;
    return 1.0;
  }

  void setDarkMode(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setFontSize(String size) {
    _fontSizeName = size;
    _fontSizeScale = _getScale(size);
    notifyListeners();
  }

  void setLinksEnabled(bool enabled) async {
    _linksEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('links_enabled', enabled);
    notifyListeners();
  }

  Future<void> togglePin(String address) async {
    if (_pinnedAddresses.contains(address)) {
      _pinnedAddresses.remove(address);
    } else {
      _pinnedAddresses.add(address);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_addresses', _pinnedAddresses.toList());
    notifyListeners();
  }

  Future<void> toggleBlock(String address) async {
    if (_blockedAddresses.contains(address)) {
      _blockedAddresses.remove(address);
    } else {
      _blockedAddresses.add(address);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_addresses', _blockedAddresses.toList());
    notifyListeners();
  }

  Future<void> addToFolder(String folderName, String sender, int messageId) async {
    if (!_folders.containsKey(folderName)) {
      _folders[folderName] = {};
    }
    if (!_folders[folderName]!.containsKey(sender)) {
      _folders[folderName]![sender] = [];
    }
    if (!_folders[folderName]![sender]!.contains(messageId)) {
      _folders[folderName]![sender]!.add(messageId);
      await _saveFolders();
    }
  }

  Future<void> removeFromFolder(String folderName, String sender, int messageId) async {
    if (_folders.containsKey(folderName) && _folders[folderName]!.containsKey(sender)) {
      _folders[folderName]![sender]!.remove(messageId);
      if (_folders[folderName]![sender]!.isEmpty) {
        _folders[folderName]!.remove(sender);
      }
      await _saveFolders();
    }
  }

  Future<void> deleteFolder(String name) async {
    _folders.remove(name);
    await _saveFolders();
  }

  Future<void> renameFolder(String oldName, String newName) async {
    if (_folders.containsKey(oldName)) {
      final data = _folders.remove(oldName);
      _folders[newName] = data!;
      await _saveFolders();
    }
  }

  Future<void> deleteSubFolder(String folderName, String sender) async {
    if (_folders.containsKey(folderName)) {
      _folders[folderName]!.remove(sender);
      await _saveFolders();
    }
  }

  Future<void> createFolder(String name) async {
    if (!_folders.containsKey(name)) {
      _folders[name] = {};
      await _saveFolders();
    }
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_folders_v3', json.encode(_folders));
    notifyListeners();
  }
}

@pragma('vm:entry-point')
void backgroundMessageHandler(tp.SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Notification is handled by the native side (SmsReceiver.kt) to avoid duplicates.
  // We only keep this for potential headless processing if needed.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    NotificationService.init(requestPermissions: true),
    AppSettings().load(),
  ]);

  NotificationService.onNotificationTap = _navigateToConversation;

  _platform.setMethodCallHandler((call) async {
    if (call.method == 'onNotificationTap') {
      final String address = call.arguments as String;
      _navigateToConversation(address);
    }
  });

  final prefs = await SharedPreferences.getInstance();
  final bool introSeen = prefs.getBool('intro_seen') ?? false;

  runApp(SoftBridgeTexts(startScreen: introSeen ? const MessageListScreen() : const IntroScreen()));

  _checkInitialNotification();
}

Future<void> _checkInitialNotification() async {
  try {
    final String? address = await _platform.invokeMethod('getInitialSmsAddress');
    if (address != null && address.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 250));
      _navigateToConversation(address);
    }
  } catch (_) {}
}

void _navigateToConversation(String address) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => ConversationScreen(address: address),
    ),
  );
}

class SoftBridgeTexts extends StatelessWidget {
  final Widget startScreen;
  const SoftBridgeTexts({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings(),
      builder: (context, _) {
        final settings = AppSettings();
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'SoftBridge Texts',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0078D4),
              brightness: Brightness.light,
            ),
            textTheme: GoogleFonts.openSansTextTheme(),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.black87,
              iconTheme: IconThemeData(color: Colors.black87),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0078D4),
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.openSansTextTheme(ThemeData.dark().textTheme),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
          ),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.fontSizeScale),
              ),
              child: child!,
            );
          },
          home: startScreen,
        );
      },
    );
  }
}

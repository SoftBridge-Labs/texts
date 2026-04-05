import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart' as tp;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import '../main.dart';
import '../models/sms_data.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/custom_popup_menu.dart';
import 'conversation_screen.dart';
import 'new_message_screen.dart';
import 'settings_screen.dart';
import 'folders_screen.dart';

class MessageListScreen extends StatefulWidget {
  const MessageListScreen({super.key});

  @override
  State<MessageListScreen> createState() => _MessageListScreenState();
}

class _MessageListScreenState extends State<MessageListScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('in.softbridgelabs.text/default_sms');
  final tp.Telephony telephony = tp.Telephony.instance;
  List<MessageData> _allMessages = [];
  final Map<String, MessageData> _conversationByAddress = {};
  List<String> _filteredAddresses = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  final Set<String> _locallyReadAddresses = {};
  bool _isSpamProtectionEnabled = true;
  SharedPreferences? _prefs;
  bool _isRefreshing = false;
  int _lastCacheSignature = 0;

  final Set<String> _selectedAddresses = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _requestPermissions();

    // Set screenshot protection at the beginning — also handled by native FLAG_SECURE
    FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isSelectionMode && !_isSearching) _refreshMessages();
    });
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isSpamProtectionEnabled = _prefs?.getBool('spam_protection') ?? true;
      });
      _loadCachedMessages().then((_) => _refreshMessages());
    }
  }

  Future<void> _loadCachedMessages() async {
    try {
      final String? cachedJson = _prefs?.getString('cached_conversations_v1');
      if (cachedJson != null) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final List<MessageData> cachedMessages = decoded.map((m) => MessageData.fromMap(Map<String, dynamic>.from(m))).toList();
        if (mounted && _allMessages.isEmpty) {
          setState(() {
            _allMessages = cachedMessages;
            _conversationByAddress
              ..clear()
              ..addEntries(cachedMessages.map((m) => MapEntry(m.address ?? 'Unknown', m)));
            _filterMessages(_searchController.text);
            _lastCacheSignature = _computeSignature(cachedMessages);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading cached messages: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isSelectionMode) {
      _refreshMessages();
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.contacts,
      if (Theme.of(context).platform == TargetPlatform.android) Permission.notification,
    ].request();

    if (statuses[Permission.sms]?.isGranted ?? false) {
      _checkDefaultSmsApp();
    } else if (statuses[Permission.sms]?.isPermanentlyDenied ?? false) {
      if (mounted) {
        _showPermissionSettingsDialog();
      }
    }
  }

  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissions Needed'),
        content: const Text('SMS permission is required to display your messages. Please enable it in app settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkDefaultSmsApp() async {
    try {
      final bool isDefault = await platform.invokeMethod('isDefaultSmsApp');
      if (!isDefault) {
        final prefs = await SharedPreferences.getInstance();
        final bool dismissed = prefs.getBool('default_sms_dismissed') ?? false;
        if (!dismissed && mounted) {
          _showDefaultSmsDialog();
        } else {
          _initTelephony();
        }
      } else {
        _initTelephony();
      }
    } on PlatformException catch (_) {
      _initTelephony();
    }
  }

  void _showDefaultSmsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Default SMS App', style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
        content: const Text('SoftBridge Texts needs to be your default SMS app to manage your messages.'),
        actions: [
          TextButton(
            onPressed: () async {
              await platform.invokeMethod('requestDefaultSmsApp');
              if (mounted) {
                Navigator.pop(dialogContext);
                _initTelephony();
              }
            },
            child: const Text('SET AS DEFAULT'),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('default_sms_dismissed', true);
              if (mounted) {
                Navigator.pop(dialogContext);
                _initTelephony();
              }
            },
            child: const Text('CONTINUE', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<void> _initTelephony() async {
    await _refreshMessages();
    telephony.listenIncomingSms(
      onNewMessage: (tp.SmsMessage message) {
        if (!_isSelectionMode) _refreshMessages();
      },
      listenInBackground: true,
      onBackgroundMessage: backgroundMessageHandler,
    );
  }

  Future<void> _refreshMessages() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      // NEW: Native speedup — only get latest message per thread instead of querying entire inbox
      final List<dynamic>? rawConversations = await platform.invokeMethod('getAllConversations');
      if (rawConversations == null) return;
      
      final messages = rawConversations.map((c) {
        final map = Map<String, dynamic>.from(c);
        return MessageData.fromMap({
          'id': map['thread_id']?.toString() ?? '0',
          'address': map['address'] ?? 'Unknown',
          'body': map['body'] ?? '',
          'date': map['date'],
          'type': map['type'],
          'read': map['read'] ? 1 : 0,
        });
      }).toList();

      final Map<String, MessageData> nextByAddress = {};
      for (final msg in messages) {
        final address = msg.address ?? 'Unknown';
        nextByAddress.putIfAbsent(address, () => msg);
      }

      final nextMessages = nextByAddress.values.toList(growable: false);
      final nextSignature = _computeSignature(nextMessages);

      if (mounted) {
        setState(() {
          _allMessages = nextMessages;
          _conversationByAddress
            ..clear()
            ..addAll(nextByAddress);
          _filterMessages(_searchController.text);

          // Clean up locally read addresses that are now officially read in DB
          for (final msg in nextMessages) {
            if ((msg.read == true) && msg.address != null) {
              _locallyReadAddresses.remove(msg.address);
            }
          }
        });
        
        // Cache only when content changed to avoid frequent IO churn.
        if (_prefs != null && nextSignature != _lastCacheSignature) {
          _lastCacheSignature = nextSignature;
          final String encoded = jsonEncode(nextMessages.map((m) => m.toMap()).toList());
          await _prefs!.setString('cached_conversations_v1', encoded);
        }
      }
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
      // If native optimization fails, the old slow way would be a fallback.. but let's hope it doesn't.
    } finally {
      _isRefreshing = false;
    }
  }

  int _computeSignature(List<MessageData> messages) {
    var hash = messages.length;
    for (final msg in messages) {
      hash = 31 * hash + (msg.address?.hashCode ?? 0);
      hash = 31 * hash + (msg.body?.hashCode ?? 0);
      hash = 31 * hash + (msg.date?.millisecondsSinceEpoch ?? 0);
      hash = 31 * hash + (msg.read == true ? 1 : 0);
    }
    return hash;
  }

  void _filterMessages(String query) {
    final settings = AppSettings();
    final normalizedQuery = query.toLowerCase();
    List<String> addresses = _conversationByAddress.keys.toList(growable: false);

    addresses = addresses.where((addr) => !settings.blockedAddresses.contains(addr)).toList();

    if (query.isNotEmpty) {
      addresses = addresses
          .where((address) => address.toLowerCase().contains(normalizedQuery))
          .toList();
    }

    if (_isSpamProtectionEnabled) {
      addresses = addresses.where((address) {
        final msg = _conversationByAddress[address];
        return msg == null || !_isSpam(msg.body ?? '', address);
      }).toList();
    }

    addresses.sort((a, b) {
      final aPinned = settings.pinnedAddresses.contains(a);
      final bPinned = settings.pinnedAddresses.contains(b);
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      final aMsg = _conversationByAddress[a];
      final bMsg = _conversationByAddress[b];
      return (bMsg?.date ?? DateTime(0)).compareTo(aMsg?.date ?? DateTime(0));
    });

    _filteredAddresses = addresses;
  }

  bool _isSpam(String body, String address) {
    final spamKeywords = ['lottery', 'won', 'cash prize', 'click here', 'urgent', 'winner', 'account suspended'];
    final lowerBody = body.toLowerCase();
    for (var keyword in spamKeywords) {
      if (lowerBody.contains(keyword)) return true;
    }
    return false;
  }

  void _toggleSelection(String address) {
    setState(() {
      if (_selectedAddresses.contains(address)) {
        _selectedAddresses.remove(address);
        if (_selectedAddresses.isEmpty) _isSelectionMode = false;
      } else {
        _selectedAddresses.add(address);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedAddresses.length == _filteredAddresses.length) {
        _selectedAddresses.clear();
        _isSelectionMode = false;
      } else {
        _selectedAddresses.clear();
        _selectedAddresses.addAll(_filteredAddresses);
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _bulkDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Conversations'),
        content: Text('Delete ${_selectedAddresses.length} selected conversations?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final addr in _selectedAddresses) {
      await platform.invokeMethod('deleteSmsThread', {'address': addr});
    }

    setState(() {
      _selectedAddresses.clear();
      _isSelectionMode = false;
    });
    _refreshMessages();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = AppSettings();

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            elevation: 0,
            leading: _isSelectionMode 
              ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                  _selectedAddresses.clear();
                  _isSelectionMode = false;
                }))
              : null,
            title: _isSelectionMode 
              ? Text('${_selectedAddresses.length} selected', style: GoogleFonts.openSans(fontWeight: FontWeight.w600))
              : _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) => setState(() => _filterMessages(value)),
                  )
                : Text('SoftBridge Texts', 
                    style: GoogleFonts.openSans(
                      fontWeight: FontWeight.bold, 
                      fontSize: 24,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A)
                    )),
            actions: _isSelectionMode ? [
              IconButton(
                icon: Icon(_selectedAddresses.length == _filteredAddresses.length ? Icons.deselect : Icons.select_all), 
                onPressed: _selectAll,
                tooltip: 'Select All',
              ),
              IconButton(icon: const Icon(Icons.push_pin_outlined), onPressed: () {
                for(var a in _selectedAddresses) settings.togglePin(a);
                setState(() { _selectedAddresses.clear(); _isSelectionMode = false; });
              }),
              IconButton(icon: const Icon(Icons.block_outlined), onPressed: () {
                for(var a in _selectedAddresses) settings.toggleBlock(a);
                setState(() { _selectedAddresses.clear(); _isSelectionMode = false; });
              }),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: _bulkDelete),
            ] : [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search_outlined),
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      _filterMessages('');
                    }
                  });
                },
              ),
              CustomPopupMenuButton<String>(
                child: Icon(Icons.more_vert, color: isDark ? Colors.white : Colors.black87),
                options: [
                  CustomPopupMenuOption(value: 'refresh', title: 'Refresh', icon: Icons.refresh),
                  CustomPopupMenuOption(value: 'folders', title: 'Custom Folders', icon: Icons.folder_open),
                  CustomPopupMenuOption(value: 'settings', title: 'Settings', icon: Icons.settings),
                ],
                onSelected: (value) async {
                  if (value == 'refresh') {
                    _refreshMessages();
                    CustomSnackbar.show(context, 'Refreshing conversation list', backgroundColor: Colors.blueAccent, icon: Icons.refresh);
                  }
                  if (value == 'folders') Navigator.push(context, MaterialPageRoute(builder: (c) => const FoldersScreen()));
                  if (value == 'settings') Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen()));
                },
              ),
            ],
          ),
          body: _allMessages.isEmpty
              ? RefreshIndicator(
                  onRefresh: _refreshMessages,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.3),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.message_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text('No messages found', style: GoogleFonts.openSans(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshMessages,
                  color: const Color(0xFF0078D4),
                  backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: _filteredAddresses.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final address = _filteredAddresses[index];
                    final lastMsg = _conversationByAddress[address];
                    if (lastMsg == null) return const SizedBox.shrink();

                    final isPinned = settings.pinnedAddresses.contains(address);
                    final isSelected = _selectedAddresses.contains(address);
                    final isUnread = lastMsg.read == false && !_locallyReadAddresses.contains(address);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: InkWell(
                        onLongPress: () => _toggleSelection(address),
                        onTap: () async {
                          if (_isSelectionMode) {
                            _toggleSelection(address);
                          } else {
                            setState(() => _locallyReadAddresses.add(address));
                            await Navigator.push(context, MaterialPageRoute(builder: (c) => ConversationScreen(address: address)));
                            _refreshMessages();
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected 
                              ? (isDark ? Colors.blue.withOpacity(0.15) : Colors.blue.withOpacity(0.08))
                              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                            borderRadius: BorderRadius.circular(16),
                            border: isSelected 
                              ? Border.all(color: const Color(0xFF0078D4).withOpacity(0.5), width: 1.5)
                              : Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02)),
                          ),
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: isSelected 
                                      ? const Color(0xFF0078D4)
                                      : const Color(0xFF0078D4).withOpacity(0.1),
                                    child: isSelected 
                                      ? const Icon(Icons.check, color: Colors.white, size: 28)
                                      : Text(address[0].toUpperCase(), 
                                          style: const TextStyle(color: Color(0xFF0078D4), fontWeight: FontWeight.bold, fontSize: 20)),
                                  ),
                                  if (isPinned)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.blue.shade100)),
                                        child: Icon(Icons.push_pin, size: 12, color: Colors.blue.shade700),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(address, 
                                          style: GoogleFonts.openSans(
                                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600, 
                                            fontSize: 16,
                                            color: isDark ? Colors.white : Colors.black87
                                          )),
                                        Text(lastMsg.date != null ? DateFormat('MMM d').format(lastMsg.date!) : '', 
                                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(lastMsg.body ?? '', 
                                            maxLines: 1, 
                                            overflow: TextOverflow.ellipsis, 
                                            style: GoogleFonts.openSans(
                                              color: isUnread ? (isDark ? Colors.white : Colors.black) : Colors.grey,
                                              fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                                              fontSize: 14
                                            )),
                                        ),
                                        if (isUnread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(left: 8),
                                            decoration: const BoxDecoration(color: Color(0xFF0078D4), shape: BoxShape.circle),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                  },
                ),
              ),
          floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (c) => const NewMessageScreen()));
              _refreshMessages();
            },
            backgroundColor: const Color(0xFF0078D4),
            elevation: 4,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        );
      }
    );
  }
}

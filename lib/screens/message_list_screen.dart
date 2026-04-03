import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:telephony/telephony.dart' as tp;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notification_service.dart';
import '../main.dart';
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
  final SmsQuery _query = SmsQuery();
  final tp.Telephony telephony = tp.Telephony.instance;
  List<SmsMessage> _allMessages = [];
  List<String> _filteredAddresses = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  final Set<String> _locallyReadAddresses = {};
  bool _isSpamProtectionEnabled = true;

  final Set<String> _selectedAddresses = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkDefaultSmsApp();

    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isSelectionMode && !_isSearching) _refreshMessages();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isSpamProtectionEnabled = prefs.getBool('spam_protection') ?? true;
      });
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
              final result = await platform.invokeMethod('requestDefaultSmsApp');
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
    try {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox, SmsQueryKind.sent],
        sort: true,
      );
      if (mounted) {
        setState(() {
          _allMessages = messages;
          _filterMessages(_searchController.text);
        });
      }
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
    }
  }

  DateTime _messageDate(SmsMessage message) {
    return message.date ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  SmsMessage? _latestMessage(List<SmsMessage> messages) {
    if (messages.isEmpty) return null;
    return messages.reduce((current, next) {
      return _messageDate(next).isAfter(_messageDate(current)) ? next : current;
    });
  }

  void _filterMessages(String query) {
    final conversations = _getConversations(_allMessages);
    final settings = AppSettings();
    List<String> addresses = conversations.keys.map((e) => e ?? 'Unknown').toList();

    addresses = addresses.where((addr) => !settings.blockedAddresses.contains(addr)).toList();

    if (query.isNotEmpty) {
      addresses = addresses
          .where((address) => address.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }

    if (_isSpamProtectionEnabled) {
      addresses = addresses.where((address) {
        final msgs = conversations[address == 'Unknown' ? null : address] ?? [];
        final lastMsg = _latestMessage(msgs);
        if (lastMsg == null) return true;
        return !_isSpam(lastMsg.body ?? '', address);
      }).toList();
    }

    addresses.sort((a, b) {
      final aPinned = settings.pinnedAddresses.contains(a);
      final bPinned = settings.pinnedAddresses.contains(b);
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      final aLatest = _latestMessage(conversations[a == 'Unknown' ? null : a] ?? []);
      final bLatest = _latestMessage(conversations[b == 'Unknown' ? null : b] ?? []);
      final aDate = aLatest != null ? _messageDate(aLatest) : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = bLatest != null ? _messageDate(bLatest) : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
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

  Map<String?, List<SmsMessage>> _getConversations(List<SmsMessage> messages) {
    Map<String?, List<SmsMessage>> conversations = {};
    for (var msg in messages) {
      if (!conversations.containsKey(msg.address)) {
        conversations[msg.address] = [];
      }
      conversations[msg.address]!.add(msg);
    }
    return conversations;
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
    final conversations = _getConversations(_allMessages);
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
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.message_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text('No messages found', style: GoogleFonts.openSans(color: Colors.grey, fontSize: 16)),
                  ],
                ))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: _filteredAddresses.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final address = _filteredAddresses[index];
                    final msgs = conversations[address == 'Unknown' ? null : address] ?? [];
                    if (msgs.isEmpty) return const SizedBox.shrink();
                    final lastMsg = _latestMessage(msgs);
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

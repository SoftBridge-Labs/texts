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
import 'transactions_screen.dart';

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
  bool _isDialogShowing = false;

  int _currentTabIndex = 0;
  String _selectedCategory = 'Transactions';
  bool _showBalance = false;

  @override
  void initState() {
    super.initState();
    _checkDefaultSmsApp();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _requestPermissions();

    _applyScreenshotProtection();

    // Immediately check for expired OTP messages on app open
    _checkOtpExpiry();

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isSelectionMode && !_isSearching) _refreshMessages();
    });
  }

  Future<void> _checkOtpExpiry() async {
    try {
      final deleted = await platform.invokeMethod<int>('checkOtpExpiry');
      if ((deleted ?? 0) > 0) {
        debugPrint('Auto-deleted $deleted expired OTP message(s) on app open');
        _refreshMessages();
      }
    } catch (_) {}
  }

  Future<void> _applyScreenshotProtection() async {
    final prefs = await SharedPreferences.getInstance();
    final screenshotProtection = prefs.getBool('screenshot_protection_enabled') ?? false;
    if (screenshotProtection) {
      FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    } else {
      FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
    }
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
      _checkOtpExpiry();
      _refreshMessages();
      _checkDefaultSmsApp();
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.contacts,
      if (Theme.of(context).platform == TargetPlatform.android) Permission.notification,
    ].request();

    if (!(statuses[Permission.sms]?.isGranted ?? false) && (statuses[Permission.sms]?.isPermanentlyDenied ?? false)) {
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
        if (mounted && !_isDialogShowing) {
          _showDefaultSmsDialog();
        }
      } else {
        _initTelephony();
      }
    } on PlatformException catch (_) {
      _initTelephony();
    }
  }

  void _showDefaultSmsDialog() {
    setState(() => _isDialogShowing = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Theme.of(context).brightness == Brightness.dark 
              ? const Color(0xFF1E1E1E) 
              : Colors.white,
          elevation: 12,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0078D4).withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.forum_outlined, size: 56, color: Color(0xFF0078D4)),
                ),
                const SizedBox(height: 28),
                Text(
                  'Default App Required',
                  style: GoogleFonts.openSans(
                    fontSize: 24, 
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'To securely manage, send, and protect your SMS conversations, SoftBridge Texts must be set as your primary messaging app.',
                  style: GoogleFonts.openSans(
                    fontSize: 15, 
                    color: Colors.grey.shade600, 
                    height: 1.5
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: () async {
                      await platform.invokeMethod('requestDefaultSmsApp');
                      if (mounted) {
                        setState(() => _isDialogShowing = false);
                        Navigator.pop(dialogContext);
                        _initTelephony();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0078D4),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(
                      'SET AS DEFAULT', 
                      style: GoogleFonts.openSans(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5)
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

    // Filter blocked addresses
    addresses = addresses.where((addr) {
      if (settings.blockedAddresses.contains(addr)) return false;
      return true;
    }).toList();

    if (query.isNotEmpty) {
      addresses = addresses.where((address) {
        // Search by address name OR by message body snippet
        final msg = _conversationByAddress[address];
        return address.toLowerCase().contains(normalizedQuery) ||
               (msg?.body?.toLowerCase().contains(normalizedQuery) ?? false);
      }).toList();
    }

    if (_currentTabIndex == 0 && !_isSearching && !_isSelectionMode) {
      addresses = addresses.where((addr) {
        final msg = _conversationByAddress[addr];
        if (msg == null) return false;
        return _categorizeMessage(addr, msg.body ?? '') == _selectedCategory;
      }).toList();
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

  String _categorizeMessage(String address, String body) {
    if (body.isEmpty) return 'Personal';
    final lowerBody = body.toLowerCase();
    if (lowerBody.contains('rs.') || lowerBody.contains('inr') || lowerBody.contains('debited') || lowerBody.contains('credited') || lowerBody.contains('otp') || lowerBody.contains('bank') || lowerBody.contains('a/c') || lowerBody.contains('acct')) {
      return 'Transactions';
    }
    if (lowerBody.contains('offer') || lowerBody.contains('discount') || lowerBody.contains('sale') || lowerBody.contains('% off') || lowerBody.contains('promo') || lowerBody.contains('cashback')) {
      return 'Promotions';
    }
    if (RegExp(r'^[+0-9]{10,}$').hasMatch(address)) {
      return 'Personal';
    }
    if (RegExp(r'^[A-Za-z\-]+$').hasMatch(address)) {
      if (address.contains('HDFC') || address.contains('SBI') || address.contains('ICICI') || address.contains('BANK')) {
        return 'Transactions';
      }
      return 'Promotions';
    }
    return 'Personal';
  }

  bool _isOfferMessage(String body) {
    final lowerBody = body.toLowerCase();
    // Exclude OTPs from offers
    if (lowerBody.contains('otp') || lowerBody.contains('one time password') || lowerBody.contains('verification code')) {
      return false;
    }
    return lowerBody.contains('offer') ||
        lowerBody.contains('discount') ||
        lowerBody.contains('sale') ||
        lowerBody.contains('% off') ||
        lowerBody.contains('promo') ||
        lowerBody.contains('cashback') ||
        lowerBody.contains('deal') ||
        lowerBody.contains('voucher') ||
        lowerBody.contains('coupon') ||
        lowerBody.contains('free') ||
        lowerBody.contains('off on') ||
        lowerBody.contains('upto') ||
        lowerBody.contains('up to');
  }

  List<Map<String, String>> _extractOffers() {
    final List<Map<String, String>> offers = [];
    final urlPattern = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    );

    for (final msg in _allMessages) {
      final body = msg.body ?? '';
      if (!_isOfferMessage(body)) continue;

      final urls = urlPattern.allMatches(body).map((m) => m.group(0)!).toList();
      final link = urls.isNotEmpty ? urls.first : '';

      // Extract a short offer description (first 120 chars)
      String preview = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (preview.length > 120) preview = '${preview.substring(0, 120)}...';

      offers.add({
        'from': msg.address ?? 'Unknown',
        'preview': preview,
        'link': link,
        'date': msg.date != null ? DateFormat('MMM d').format(msg.date!) : '',
        'id': msg.id ?? '',
        'address': msg.address ?? 'Unknown',
      });
    }

    return offers;
  }

  List<Map<String, String>> _extractBankAccounts() {
    final Map<String, Map<String, String>> accounts = {};

    String _cleanBankName(String address) {
      String name = address;
      if (name.contains('-')) {
        name = name.split('-').last;
      }
      name = name.replaceAll(RegExp(r'(BK|BNK|BANK|SMS|MSG)$', caseSensitive: false), '');
      return name.toUpperCase();
    }

    for (var msg in _allMessages) {
      final body = msg.body ?? '';
      final lowerBody = body.toLowerCase();
      final address = msg.address ?? '';

      if (lowerBody.contains('a/c') || lowerBody.contains('acct') || lowerBody.contains('account') || lowerBody.contains('ending')) {
        final accMatch = RegExp(r'(?:a\/c|acct|account|ending.*?)\s*[xX*]{0,4}\*?-?(\d{4})', caseSensitive: false).firstMatch(body);

        if (accMatch != null) {
          final last4 = accMatch.group(1)!;
          final bankName = _cleanBankName(address);
          final key = '$bankName$last4';

          String balanceInfo = 'Recently updated';
          final dateMatch = RegExp(r'on\s+(\d{1,2}\s+[a-zA-Z]{3})', caseSensitive: false).firstMatch(body);
          if (dateMatch != null) {
            balanceInfo = 'Avbl bal on ${dateMatch.group(1)}';
          }

          // Try to extract actual available balance amount
          String amount = '';
          final amountMatch = RegExp(
            r'(?:avail(?:able)?\s*(?:bal(?:ance)?)?|bal(?:ance)?)[:\s]*(?:INR|Rs\.?|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
            caseSensitive: false,
          ).firstMatch(body);
          if (amountMatch != null) {
            amount = '₹${amountMatch.group(1)!.replaceAll(',', '')}'
                .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
          } else {
            // Try generic INR/Rs amount pattern
            final genericMatch = RegExp(
              r'(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)',
              caseSensitive: false,
            ).firstMatch(body);
            if (genericMatch != null) {
              amount = '₹${genericMatch.group(1)!}';
            }
          }

          if (!accounts.containsKey(key)) {
            accounts[key] = {
              'bank': bankName,
              'last4': last4,
              'balance': balanceInfo,
              'amount': amount,
            };
          } else {
            if (balanceInfo != 'Recently updated') {
              accounts[key]!['balance'] = balanceInfo;
            }
            if (amount.isNotEmpty && accounts[key]!['amount']!.isEmpty) {
              accounts[key]!['amount'] = amount;
            }
          }
        }
      }
    }

    final sortedList = accounts.values.toList();
    sortedList.sort((a, b) => a['bank']!.compareTo(b['bank']!));
    return sortedList;
  }


  Widget _buildFinanceTab(bool isDark) {
    final accounts = _extractBankAccounts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Show balance', style: TextStyle(fontSize: 18, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Extracted from SMS, actual may vary', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              Switch(value: _showBalance, onChanged: (v) => setState(() => _showBalance = v), activeColor: Colors.blue),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 8),
              Text('Recently updated from SMS', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Icon(Icons.account_balance, color: isDark ? Colors.white : Colors.black, size: 18),
              const SizedBox(width: 8),
              Text('Accounts', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: accounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('No accounts detected', style: GoogleFonts.openSans(color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Bank account details will appear here\nonce you receive transaction SMS', textAlign: TextAlign.center, style: GoogleFonts.openSans(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: accounts.length,
                  separatorBuilder: (context, index) => Divider(color: isDark ? Colors.white24 : Colors.black12, thickness: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final acc = accounts[index];
                    final hasAmount = acc['amount'] != null && acc['amount']!.isNotEmpty;
                    return ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TransactionsScreen(
                              bankName: acc['bank']!,
                              last4: acc['last4']!,
                            ),
                          ),
                        );
                      },
                      title: Text('${acc['bank']} ••${acc['last4']}', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                      subtitle: Text(acc['balance']!, style: TextStyle(color: Colors.grey, fontSize: 13)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_showBalance)
                            Text(
                              hasAmount ? acc['amount']! : 'N/A',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            )
                          else
                            Text('₹ •••••', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.shield, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('We do not upload your SMS data anywhere. Your personal information stays on your device.', style: TextStyle(color: Colors.grey, fontSize: 11))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOffersTab(bool isDark) {
    final offers = _extractOffers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.local_offer_rounded, color: const Color(0xFF0078D4), size: 20),
              const SizedBox(width: 8),
              Text('${offers.length} Offer${offers.length == 1 ? '' : 's'} found', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
            ],
          ),
        ),
        Expanded(
          child: offers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.discount_outlined, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('No offers found', style: GoogleFonts.openSans(color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Offer and discount SMS will appear here', style: GoogleFonts.openSans(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: offers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final offer = offers[index];
                    final hasLink = offer['link'] != null && offer['link']!.isNotEmpty;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0078D4).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(offer['from']!, style: const TextStyle(color: Color(0xFF0078D4), fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ),
                              Text(offer['date']!, style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(offer['preview']!, style: GoogleFonts.openSans(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (hasLink)
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final settings = AppSettings();
                                      if (!settings.linksEnabled) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text('Enable links in Settings to open URLs'),
                                            action: SnackBarAction(label: 'Settings', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen()))),
                                          ),
                                        );
                                        return;
                                      }
                                      try {
                                        await platform.invokeMethod('openUrl', {'url': offer['link']});
                                      } catch (e) {
                                        debugPrint('Error opening URL: $e');
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0078D4).withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF0078D4).withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.link, size: 14, color: Color(0xFF0078D4)),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Open Link',
                                              style: const TextStyle(color: Color(0xFF0078D4), fontSize: 12, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (hasLink) const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (c) => ConversationScreen(address: offer['address']!)),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.forum_outlined, size: 14, color: isDark ? Colors.white70 : Colors.black87),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Full Chat',
                                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, bool isSelected, bool isDark, {bool isSimple = false}) {
    // Compute unread count for the category to decide whether to show the dot
    bool _hasUnread = false;
    if (!isSimple) {
      _hasUnread = _conversationByAddress.entries.any((entry) {
        final addr = entry.key;
        final msg = entry.value;
        final isUnread = msg.read == false && !_locallyReadAddresses.contains(addr);
        return isUnread && _categorizeMessage(addr, msg.body ?? '') == label;
      });
    }

    return InkWell(
      onTap: () {
        if (!isSimple) {
          setState(() {
            _selectedCategory = label;
            _filterMessages(_searchController.text);
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? Colors.blueAccent.withOpacity(0.4) : Colors.blue.shade100) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.transparent : (isDark ? Colors.white24 : Colors.black26)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: isSelected ? (isDark ? Colors.white : Colors.blue.shade900) : (isDark ? Colors.white54 : Colors.black54), fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            if (!isSimple && _hasUnread) ...[
              const SizedBox(width: 6),
              Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.red.shade400, shape: BoxShape.circle)),
            ],
          ],
        ),
      ),
    );
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
              ? IconButton(
                  icon: const Icon(Icons.close), 
                  onPressed: () => setState(() {
                    _selectedAddresses.clear();
                    _isSelectionMode = false;
                  }),
                )
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
                : Text(
                    _currentTabIndex == 0 ? 'Messages' : _currentTabIndex == 1 ? 'Finance' : 'Offers', 
                    style: GoogleFonts.openSans(
                      fontWeight: FontWeight.bold, 
                      fontSize: 24,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
            actions: _isSelectionMode ? [
              IconButton(
                icon: Icon(_selectedAddresses.length == _filteredAddresses.length ? Icons.deselect : Icons.select_all), 
                onPressed: _selectAll,
                tooltip: 'Select All',
              ),
              IconButton(
                icon: const Icon(Icons.push_pin_outlined), 
                onPressed: () {
                  for(var a in _selectedAddresses) settings.togglePin(a);
                  setState(() { _selectedAddresses.clear(); _isSelectionMode = false; });
                },
              ),
              IconButton(
                icon: const Icon(Icons.block_outlined), 
                onPressed: () {
                  for(var a in _selectedAddresses) settings.toggleBlock(a);
                  setState(() { _selectedAddresses.clear(); _isSelectionMode = false; });
                },
              ),
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
          body: _currentTabIndex == 1 
            ? _buildFinanceTab(isDark) 
            : _currentTabIndex == 2 
                ? _buildOffersTab(isDark) 
                : Column(
                    children: [
                      if (!_isSelectionMode && !_isSearching) 
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildChip('Personal', _selectedCategory == 'Personal', isDark),
                                const SizedBox(width: 8),
                                _buildChip('Transactions', _selectedCategory == 'Transactions', isDark),
                                const SizedBox(width: 8),
                                _buildChip('Promotions', _selectedCategory == 'Promotions', isDark),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: _allMessages.isEmpty
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
                                                            color: isDark ? Colors.white : Colors.black87,
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
                                                              fontSize: 14,
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
                      )
                    ],
                  ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentTabIndex,
            onTap: (index) {
              setState(() {
                _currentTabIndex = index;
                if (index == 0) _filterMessages(_searchController.text);
              });
            },
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
              BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Finance'),
              BottomNavigationBarItem(icon: Icon(Icons.local_offer_outlined), label: 'Offers'),
            ],
          ),
          floatingActionButton: _isSelectionMode || _currentTabIndex != 0 ? null : FloatingActionButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (c) => const NewMessageScreen()));
              _refreshMessages();
            },
            backgroundColor: const Color(0xFF0078D4),
            elevation: 4,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        );
      },
    );
  }
}

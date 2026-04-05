import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:telephony/telephony.dart' as tp;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart';
import '../models/sms_data.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/custom_snackbar.dart';
import '../widgets/custom_popup_menu.dart';

class ConversationScreen extends StatefulWidget {
  final String address;
  const ConversationScreen({super.key, required this.address});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const platform = MethodChannel('in.softbridgelabs.text/default_sms');
  final TextEditingController _controller = TextEditingController();
  final tp.Telephony telephony = tp.Telephony.instance;
  final SmsQuery _query = SmsQuery();
  
  List<MessageData> _currentMessages = [];
  bool _isLoading = true;

  final Set<int> _selectedMessageIds = {};
  bool _isSelectionMode = false;
  bool _showTick = false;

  void _showSatisfyingTick() {
    setState(() => _showTick = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showTick = false);
    });
  }

  @override
  void initState() {
    super.initState();
    FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final messages = await _queryMessagesForAddress(widget.address);
    if (mounted) {
      setState(() {
        _currentMessages = messages;
        _isLoading = false;
      });
    }
    _markAsRead();
  }

  Future<List<MessageData>> _queryMessagesForAddress(String address) async {
    try {
      // NEW: Highly optimized native query instead of Dart-side filtering
      final List<dynamic>? rawMessages = await platform.invokeMethod('getMessagesForAddress', {'address': address});
      if (rawMessages == null) return [];
      
      return rawMessages.map((m) {
        final map = Map<String, dynamic>.from(m);
        return MessageData.fromMap({
          'id': map['id'].toString(),
          'address': map['address'],
          'body': map['body'],
          'date': map['date'],
          'type': map['type'],
          'read': map['read'] ? 1 : 0,
        });
      }).toList();
    } catch (e) {
      debugPrint('Error loading conversation: $e');
      return [];
    }
  }

  Future<void> _markAsRead() async {
    try {
      await platform.invokeMethod('markSmsAsRead', {'address': widget.address});
    } catch (_) {}
  }

  void _sendMessage() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    try {
      await telephony.sendSms(to: widget.address, message: text);
      
      // Play satisfying sound
      AudioPlayer().play(AssetSource('lib/sounds/send.mp3'));
      
      if (mounted) {
        _showSatisfyingTick();
      }
      Future.delayed(const Duration(seconds: 2), _loadMessages);
    } catch (e) {
      if (mounted) CustomSnackbar.show(context, 'Error: $e', backgroundColor: Colors.redAccent, icon: Icons.error_outline);
    }
  }

  void _toggleMessageSelection(int? id) {
    if (id == null) return;
    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.remove(id);
        if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedMessageIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAllMessages() {
    setState(() {
      if (_selectedMessageIds.length == _currentMessages.length) {
        _selectedMessageIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedMessageIds.clear();
        for (var msg in _currentMessages) {
          final id = int.tryParse(msg.id?.toString() ?? '');
          if (id != null) _selectedMessageIds.add(id);
        }
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelectedMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Messages'),
        content: Text('Delete ${_selectedMessageIds.length} selected messages?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final id in _selectedMessageIds) {
      try {
        await platform.invokeMethod('deleteSmsMessage', {'id': id});
      } catch (e) {
        debugPrint('Error deleting message $id: $e');
      }
    }

    setState(() {
      _selectedMessageIds.clear();
      _isSelectionMode = false;
    });
    _loadMessages();
  }

  void _showMoveChatDialog() {
    final settings = AppSettings();
    final folders = settings.folders.keys.toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Move Conversation to Folder', style: GoogleFonts.openSans(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('No folders created yet. Please create one in Custom Folders.', style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    tileColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.folder_rounded, color: Color(0xFF0078D4)),
                    title: Text(folders[i], style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
                    onTap: () {
                      for (var msg in _currentMessages) {
                        final id = int.tryParse(msg.id?.toString() ?? '');
                        if (id != null) settings.addToFolder(folders[i], widget.address, id);
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Saved to ${folders[i]}'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        )
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLink(String url) async {
    final settings = AppSettings();
    if (!settings.linksEnabled) {
      CustomSnackbar.show(context, 'Links are disabled. Enable them in Settings.', backgroundColor: Colors.orange.shade800, icon: Icons.link_off);
      return;
    }

    final confirmed = await _scanAndConfirmLink(url);
    if (confirmed == true) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) CustomSnackbar.show(context, 'Could not open link', backgroundColor: Colors.redAccent);
      }
    }
  }

  Future<bool?> _scanAndConfirmLink(String url) async {
    // Show Scanning Modal
    final scanResult = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ScanLoadingModal(url: url),
    );

    if (scanResult == null) return false;

    final String verdict = scanResult['verdict'] ?? 'UNKNOWN';
    final String emoji = scanResult['verdictEmoji'] ?? '🛡️';
    final String finalUrl = scanResult['finalUrl'] ?? url;
    final bool isSafe = verdict == 'SAFE';
    final List<dynamic> reasons = scanResult['heuristics']?['reasons'] ?? [];

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(child: Text(isSafe ? 'Looks Safe' : 'Security Warning', style: GoogleFonts.openSans(fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isSafe ? 'Our automated scan didn\'t find any immediate threats. Continue with caution.' : 'This link appears to be suspicious or potentially harmful.', 
              style: GoogleFonts.openSans(fontSize: 14, color: isSafe ? Colors.grey.shade700 : Colors.red.shade800)),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...reasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange), const SizedBox(width: 8), Text(r.toString(), style: const TextStyle(fontSize: 12, color: Colors.orange))]),
              )),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('ORIGINAL LINK:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(url, style: const TextStyle(fontSize: 11, color: Colors.blue), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (finalUrl != url) ...[
              const SizedBox(height: 8),
              const Text('EXPANDED TO:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text(finalUrl, style: const TextStyle(fontSize: 11, color: Colors.red), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSafe ? const Color(0xFF0078D4) : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true), 
            child: Text(isSafe ? 'OPEN LINK' : 'PROCEED ANYWAY'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isBlocked = settings.blockedAddresses.contains(widget.address);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        leading: _isSelectionMode 
          ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
              _selectedMessageIds.clear();
              _isSelectionMode = false;
            }))
          : null,
        title: _isSelectionMode 
          ? Text('${_selectedMessageIds.length} selected', style: GoogleFonts.openSans(fontWeight: FontWeight.w600))
          : Text(widget.address, style: GoogleFonts.openSans(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        actions: _isSelectionMode ? [
          IconButton(
            icon: Icon(_selectedMessageIds.length == _currentMessages.length ? Icons.deselect : Icons.select_all), 
            onPressed: _selectAllMessages,
            tooltip: 'Select All',
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteSelectedMessages),
        ] : [
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: _showMoveChatDialog,
            tooltip: 'Move to Folder',
          ),
          CustomPopupMenuButton<String>(
            child: const Icon(Icons.more_vert),
            options: [
              CustomPopupMenuOption(value: 'block', title: isBlocked ? 'Unblock' : 'Block', icon: isBlocked ? Icons.lock_open : Icons.block),
            ],
            onSelected: (val) {
              if (val == 'block') {
                settings.toggleBlock(widget.address);
                CustomSnackbar.show(context, isBlocked ? 'Unblocked ${widget.address}' : 'Blocked ${widget.address}', icon: isBlocked ? Icons.lock_open : Icons.block);
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _currentMessages.length,
                  itemBuilder: (context, index) {
                    final msg = _currentMessages[index];
                    final isMe = msg.kind == SmsMessageKind.sent;
                    final id = int.tryParse(msg.id?.toString() ?? '');
                    final isSelected = id != null && _selectedMessageIds.contains(id);
                    
                    return GestureDetector(
                      onLongPress: () => _toggleMessageSelection(id),
                      onTap: () {
                        if (_isSelectionMode) {
                          _toggleMessageSelection(id);
                        }
                      },
                      child: _buildMessageBubble(msg, msg.kind == SmsMessageKind.sent, isDark, isSelected),
                    );
                  },
                ),
          ),
          if (!_isSelectionMode) _buildInputArea(isDark, isBlocked),
        ],
      ).animate(target: _showTick ? 1 : 0).blur(begin: Offset.zero, end: const Offset(4, 4), duration: 400.ms, curve: Curves.easeInOut),
      floatingActionButton: _showTick ? Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF0078D4).withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 60)
        ).animate().scale(duration: 400.ms, curve: Curves.elasticOut).fadeOut(delay: 1000.ms),
      ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildMessageBubble(MessageData msg, bool isMe, bool isDark, bool isSelected) {
    final text = msg.body ?? '';
    final urlRegExp = RegExp(r'https?://[^\s]+');
    final hasLinks = urlRegExp.hasMatch(text);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isSelected 
            ? (isMe ? const Color(0xFF00569E) : (isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE3F2FD)))
            : (isMe ? const Color(0xFF0078D4) : (isDark ? const Color(0xFF2C2C2C) : Colors.white)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isSelected ? Border.all(color: Colors.blue, width: 1) : null,
          boxShadow: [
            if (!isMe && !isSelected) BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!hasLinks)
              Text(text, style: GoogleFonts.openSans(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 15))
            else
              _buildRichTextWithLinks(text, isMe, isDark),
            const SizedBox(height: 4),
            Text(msg.date != null ? DateFormat('jm').format(msg.date!) : '', 
                 style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRichTextWithLinks(String text, bool isMe, bool isDark) {
    final List<InlineSpan> spans = [];
    final urlRegExp = RegExp(r'https?://[^\s]+');
    
    int lastMatchEnd = 0;
    for (final match in urlRegExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: GoogleFonts.openSans(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 15),
        ));
      }
      
      final url = match.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: () => _handleLink(url),
          child: Text(
            url,
            style: GoogleFonts.openSans(
              color: isMe ? Colors.lightBlue.shade100 : Colors.blue.shade700,
              fontSize: 15,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ));
      lastMatchEnd = match.end;
    }
    
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: GoogleFonts.openSans(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 15),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildInputArea(bool isDark, bool isBlocked) {
    if (isBlocked) return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
      color: Colors.red.withOpacity(0.05),
      child: Text('This contact is blocked.', textAlign: TextAlign.center, style: GoogleFonts.openSans(color: Colors.red, fontWeight: FontWeight.bold)),
    );
    
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F3F3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 5,
                minLines: 1,
                style: GoogleFonts.openSans(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            backgroundColor: const Color(0xFF0078D4),
            radius: 22,
            child: IconButton(
              onPressed: _sendMessage, 
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20)
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanLoadingModal extends StatefulWidget {
  final String url;
  const _ScanLoadingModal({required this.url});

  @override
  State<_ScanLoadingModal> createState() => _ScanLoadingModalState();
}

class _ScanLoadingModalState extends State<_ScanLoadingModal> {
  String _status = 'Initializing security scan...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _performScan();
  }

  Future<void> _performScan() async {
    try {
      setState(() { _status = 'Connecting to safety server...'; _progress = 0.2; });
      await Future.delayed(const Duration(milliseconds: 600));

      setState(() { _status = 'Checking URL reputation...'; _progress = 0.5; });
      
      final response = await http.post(
        Uri.parse('https://api.softbridgelabs.in/api/texts/scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': widget.url}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() { _status = 'Finalizing report...'; _progress = 0.9; });
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.pop(context, jsonDecode(response.body));
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0078D4)),
                  ),
                ).animate(onPlay: (c) => c.repeat()).rotate(duration: 3.seconds),
                const Icon(Icons.security_rounded, size: 32, color: Color(0xFF0078D4))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 1.seconds),
              ],
            ),
            const SizedBox(height: 24),
            Text('Scaling URL Safety', 
              style: GoogleFonts.openSans(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            Text(_status, 
              textAlign: TextAlign.center,
              style: GoogleFonts.openSans(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _progress,
                child: Container(decoration: BoxDecoration(color: const Color(0xFF0078D4), borderRadius: BorderRadius.circular(2))),
              ),
            ).animate().shimmer(duration: 1.seconds, color: Colors.white.withOpacity(0.5)),
          ],
        ),
      ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack).fadeIn(),
    );
  }
}

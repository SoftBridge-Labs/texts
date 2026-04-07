import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart' as tp;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';


class NewMessageScreen extends StatefulWidget {
  final String? initialMessage;
  const NewMessageScreen({super.key, this.initialMessage});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<Contact> _selectedContacts = [];
  final List<String> _manualNumbers = [];
  bool _isSending = false;
  DateTime? _scheduledDate;
  static const _platform = MethodChannel('in.softbridgelabs.text/default_sms');

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null) {
      _messageController.text = widget.initialMessage!;
    }
  }

  Future<void> _pickContact() async {
    try {
      if (await FlutterContacts.requestPermission()) {
        final contacts = await FlutterContacts.openExternalPick();
        if (contacts != null) {
          setState(() {
            _selectedContacts.add(contacts);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open contacts: $e')),
        );
      }
    }
  }

  void _addManualNumber() {
    final number = _addressController.text.trim();
    if (number.isNotEmpty) {
      setState(() {
        if (!_manualNumbers.contains(number)) {
          _manualNumbers.add(number);
        }
        _addressController.clear();
      });
    }
  }

  Future<void> _sendMessage() async {
    final List<String> recipients = [
      ..._selectedContacts.expand((c) => c.phones.map((p) => p.number.replaceAll(RegExp(r'[^\d+]'), ''))),
      ..._manualNumbers,
    ];

    if (recipients.isEmpty && _addressController.text.isNotEmpty) {
      recipients.add(_addressController.text.trim());
    }

    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one recipient'), behavior: SnackBarBehavior.floating));
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a message'), behavior: SnackBarBehavior.floating));
      return;
    }

    setState(() => _isSending = true);

    try {
      final String text = _messageController.text;
      for (final recipient in recipients) {
        if (_scheduledDate == null) {
          await tp.Telephony.instance.sendSms(
            to: recipient,
            message: text,
          );
        } else {
          await _platform.invokeMethod('scheduleSms', {
            'address': recipient,
            'body': text,
            'scheduledMs': _scheduledDate!.millisecondsSinceEpoch,
          });
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_scheduledDate == null 
              ? 'Message sent to ${recipients.length} recipient(s)'
              : 'Message scheduled for ${DateFormat('MMM d, h:mm a').format(_scheduledDate!)}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade600,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickScheduleTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(minutes: 5)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    final schedule = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (schedule.isBefore(DateTime.now())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot schedule in the past')));
      return;
    }
    setState(() => _scheduledDate = schedule);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('New Message', style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recipients', style: GoogleFonts.openSans(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedContacts.isNotEmpty || _manualNumbers.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ..._selectedContacts.map((contact) => Chip(
                                avatar: CircleAvatar(
                                  backgroundColor: const Color(0xFF0078D4),
                                  child: Text(contact.displayName[0], style: const TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                                label: Text(contact.displayName, style: const TextStyle(fontSize: 12)),
                                onDeleted: () => setState(() => _selectedContacts.remove(contact)),
                                deleteIcon: const Icon(Icons.cancel, size: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                backgroundColor: isDark ? Colors.white10 : Colors.blue.shade50,
                              )),
                              ..._manualNumbers.map((number) => Chip(
                                label: Text(number, style: const TextStyle(fontSize: 12)),
                                onDeleted: () => setState(() => _manualNumbers.remove(number)),
                                deleteIcon: const Icon(Icons.cancel, size: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                backgroundColor: isDark ? Colors.white10 : Colors.blue.shade50,
                              )),
                            ],
                          ),
                          const Divider(height: 24),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _addressController,
                                style: GoogleFonts.openSans(fontSize: 15),
                                decoration: const InputDecoration(
                                  hintText: 'Enter name or number',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.phone,
                                onSubmitted: (_) => _addManualNumber(),
                              ),
                            ),
                            IconButton(
                              onPressed: _pickContact,
                              icon: const Icon(Icons.contacts_rounded, color: Color(0xFF0078D4)),
                              tooltip: 'Select from contacts',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Message', style: GoogleFonts.openSans(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _messageController,
                          style: GoogleFonts.openSans(fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'What\'s on your mind?',
                            border: InputBorder.none,
                          ),
                          maxLines: 8,
                          minLines: 3,
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.schedule_rounded, 
                            color: _scheduledDate != null ? const Color(0xFF0078D4) : Colors.grey),
                          title: Text(_scheduledDate == null 
                            ? 'Schedule message (optional)' 
                            : 'Scheduled for: ${DateFormat('MMM d, h:mm a').format(_scheduledDate!)}',
                            style: GoogleFonts.openSans(
                              fontSize: 13, 
                              color: _scheduledDate != null ? const Color(0xFF0078D4) : Colors.grey,
                              fontWeight: _scheduledDate != null ? FontWeight.bold : FontWeight.normal
                            )),
                          trailing: _scheduledDate != null 
                            ? IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => setState(() => _scheduledDate = null))
                            : const Icon(Icons.chevron_right_rounded),
                          onTap: _pickScheduleTime,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSending ? null : _sendMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSending 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text('Send Message', style: GoogleFonts.openSans(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../models/sms_data.dart';

class TransactionsScreen extends StatefulWidget {
  final String bankName;
  final String last4;

  const TransactionsScreen({super.key, required this.bankName, required this.last4});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  static const platform = MethodChannel('in.softbridgelabs.text/default_sms');
  List<MessageData> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    // We need to find the correct address for this bank name to query
    // This is a bit tricky since bank name is cleaned up. 
    // In a real app, we'd pass the actual address too.
    // For now, let's query all and filter, or improve the logic.
    // Let's assume we can query messages and filter by body containing the last4 and address containing bankName.
    
    try {
      final List<dynamic>? rawConversations = await platform.invokeMethod('getAllConversations');
      if (rawConversations == null) return;

      List<MessageData> matched = [];
      
      for (var c in rawConversations) {
        final map = Map<String, dynamic>.from(c);
        final address = map['address'] as String? ?? '';
        
        // Basic match for bank name in address
        if (address.contains(widget.bankName) || widget.bankName.contains(address.split('-').last)) {
           final List<dynamic>? rawMessages = await platform.invokeMethod('getMessagesForAddress', {'address': address});
           if (rawMessages != null) {
             for (var m in rawMessages) {
               final mMap = Map<String, dynamic>.from(m);
               final body = mMap['body'] as String? ?? '';
               if (body.contains(widget.last4)) {
                 matched.add(MessageData.fromMap({
                    'id': mMap['id'].toString(),
                    'address': address,
                    'body': body,
                    'date': mMap['date'],
                    'type': mMap['type'],
                    'read': mMap['read'] ? 1 : 0,
                 }));
               }
             }
           }
        }
      }

      matched.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));

      if (mounted) {
        setState(() {
          _transactions = matched;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('${widget.bankName} ••${widget.last4}', style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? Center(child: Text('No transactions found', style: GoogleFonts.openSans(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _transactions.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tx = _transactions[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('MMM d, yyyy • h:mm a').format(tx.date ?? DateTime.now()),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              if (tx.body!.toLowerCase().contains('debited'))
                                const Icon(Icons.arrow_downward, color: Colors.red, size: 14)
                              else if (tx.body!.toLowerCase().contains('credited'))
                                const Icon(Icons.arrow_upward, color: Colors.green, size: 14),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(tx.body!, style: GoogleFonts.openSans(fontSize: 14)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

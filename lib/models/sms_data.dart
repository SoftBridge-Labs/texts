import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

/// A wrapper to handle native message data efficiently while maintaining 
/// compatibility with existing UI code.
class MessageData {
  final String? id;
  final String? address;
  final String? body;
  final DateTime? date;
  final bool? read;
  final int? type;

  MessageData({this.id, this.address, this.body, this.date, this.read, this.type});

  factory MessageData.fromMap(Map<String, dynamic> map) {
    return MessageData(
      id: map['id']?.toString() ?? map['thread_id']?.toString(),
      address: map['address'],
      body: map['body'],
      date: map['date'] != null ? DateTime.fromMillisecondsSinceEpoch(map['date'] as int) : null,
      read: map['read'] == true || map['read'] == 1,
      type: map['type'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'address': address,
      'body': body,
      'date': date?.millisecondsSinceEpoch,
      'read': read,
      'type': type,
    };
  }

  SmsMessageKind get kind => (type == 2) ? SmsMessageKind.sent : SmsMessageKind.received;
}

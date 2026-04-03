import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import '../main.dart';

class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = AppSettings();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final folderNames = settings.folders.keys.toList();

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
          appBar: AppBar(
            title: Text('Custom Folders', style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            elevation: 0,
          ),
          body: folderNames.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No custom folders yet', style: GoogleFonts.openSans(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: folderNames.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final name = folderNames[index];
                    final sendersCount = settings.folders[name]?.length ?? 0;
                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => FolderSendersScreen(folderName: name)),
                      ),
                      onLongPress: () => _showFolderOptions(context, name),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_rounded, color: Color(0xFF0078D4), size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: GoogleFonts.openSans(fontWeight: FontWeight.bold, fontSize: 17)),
                                  Text('$sendersCount conversation${sendersCount == 1 ? '' : 's'}', style: GoogleFonts.openSans(fontSize: 13, color: Colors.grey)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCreateFolderDialog(context),
            backgroundColor: const Color(0xFF0078D4),
            icon: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
            label: Text('New Folder', style: GoogleFonts.openSans(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        );
      },
    );
  }

  void _showFolderOptions(BuildContext context, String folderName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename Folder'),
              onTap: () {
                Navigator.pop(context);
                _showRenameFolderDialog(context, folderName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Folder', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context, folderName);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(BuildContext context, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                AppSettings().renameFolder(oldName, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, String folderName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to delete "$folderName"? All saved message records in this folder will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              AppSettings().deleteFolder(folderName);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Create Folder', style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Work, Family',
            filled: true,
            fillColor: Colors.grey.withOpacity(0.1),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                AppSettings().createFolder(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class FolderSendersScreen extends StatelessWidget {
  final String folderName;
  const FolderSendersScreen({super.key, required this.folderName});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final senders = settings.folders[folderName]?.keys.toList() ?? [];

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
          appBar: AppBar(
            title: Text(folderName, style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          ),
          body: senders.isEmpty
              ? Center(child: Text('No conversations in this folder', style: GoogleFonts.openSans(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: senders.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sender = senders[index];
                    final count = settings.folders[folderName]![sender]!.length;
                    return ListTile(
                      tileColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF0078D4).withOpacity(0.1),
                        child: Text(sender[0].toUpperCase(), style: const TextStyle(color: Color(0xFF0078D4))),
                      ),
                      title: Text(sender, style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
                      subtitle: Text('$count message${count == 1 ? '' : 's'}'),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => FolderDetailScreen(folderName: folderName, sender: sender)),
                      ),
                      onLongPress: () => _showSubFolderOptions(context, folderName, sender),
                    );
                  },
                ),
        );
      },
    );
  }

  void _showSubFolderOptions(BuildContext context, String folderName, String sender) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove from Folder', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showRemoveSenderConfirmation(context, folderName, sender);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveSenderConfirmation(BuildContext context, String folderName, String sender) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Conversation'),
        content: Text('Remove all messages from "$sender" from this folder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              AppSettings().deleteSubFolder(folderName, sender);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class FolderDetailScreen extends StatefulWidget {
  final String folderName;
  final String sender;
  const FolderDetailScreen({super.key, required this.folderName, required this.sender});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = AppSettings();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final messageIds = settings.folders[widget.folderName]?[widget.sender] ?? [];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.sender, style: GoogleFonts.openSans(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      body: FutureBuilder<List<SmsMessage>>(
        future: _loadFolderMessages(messageIds),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final messages = snapshot.data ?? [];
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final msg = messages[index];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat('MMM d, jm').format(msg.date ?? DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(msg.body ?? '', style: GoogleFonts.openSans(fontSize: 14)),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          settings.removeFromFolder(widget.folderName, widget.sender, int.parse(msg.id!.toString()));
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<SmsMessage>> _loadFolderMessages(List<int> ids) async {
    if (ids.isEmpty) return [];
    final query = SmsQuery();
    final all = await query.querySms(kinds: [SmsQueryKind.inbox, SmsQueryKind.sent]);
    return all.where((m) => ids.contains(int.tryParse(m.id?.toString() ?? ''))).toList();
  }
}

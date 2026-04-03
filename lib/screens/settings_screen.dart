import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _appSettings = AppSettings();

  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _otpAutoDelete = true;
  int _otpDeleteMinutes = 10;
  bool _spamProtection = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _soundEnabled = prefs.getBool('sound_enabled') ?? true;
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _otpAutoDelete = prefs.getBool('otp_auto_delete_enabled') ?? true;
      _otpDeleteMinutes = prefs.getInt('otp_delete_minutes') ?? 10;
      _spamProtection = prefs.getBool('spam_protection') ?? true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appSettings,
      builder: (context, _) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color tileColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final Color sectionTextColor = isDark ? Colors.white70 : Colors.black54;

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F3F3),
          appBar: AppBar(
            title: Text('Settings', style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            children: [
              _buildSection('Notifications', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.notifications_outlined,
                title: 'Enable Notifications',
                subtitle: 'Show alerts for new messages',
                value: _notificationsEnabled,
                onChanged: (v) {
                  setState(() => _notificationsEnabled = v);
                  _saveBool('notifications_enabled', v);
                },
              ),
              if (_notificationsEnabled) ...[
                _buildSwitchTile(
                  tileColor: tileColor,
                  icon: Icons.volume_up_outlined,
                  title: 'Notification Sound',
                  subtitle: 'Play sound for new messages',
                  value: _soundEnabled,
                  onChanged: (v) {
                    setState(() => _soundEnabled = v);
                    _saveBool('sound_enabled', v);
                  },
                ),
                _buildSwitchTile(
                  tileColor: tileColor,
                  icon: Icons.vibration_outlined,
                  title: 'Vibration',
                  subtitle: 'Vibrate for new messages',
                  value: _vibrationEnabled,
                  onChanged: (v) {
                    setState(() => _vibrationEnabled = v);
                    _saveBool('vibration_enabled', v);
                  },
                ),
              ],

              _buildSection('OTP Messages', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.timer_outlined,
                title: 'Auto-delete OTP messages',
                subtitle: 'Automatically remove OTP SMS after a set time',
                value: _otpAutoDelete,
                onChanged: (v) {
                  setState(() => _otpAutoDelete = v);
                  _saveBool('otp_auto_delete_enabled', v);
                },
              ),
              if (_otpAutoDelete)
                _buildTappableTile(
                  tileColor: tileColor,
                  icon: Icons.av_timer_outlined,
                  title: 'Delete OTP after',
                  subtitle: '$_otpDeleteMinutes minutes',
                  onTap: () => _showOtpTimerDialog(),
                ),

              _buildSection('Appearance', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.dark_mode_outlined,
                title: 'Dark Mode',
                subtitle: 'Use dark colour scheme',
                value: _appSettings.themeMode == ThemeMode.dark,
                onChanged: (v) {
                  _appSettings.setDarkMode(v);
                  _saveBool('dark_mode', v);
                },
              ),
              _buildTappableTile(
                tileColor: tileColor,
                icon: Icons.format_size_outlined,
                title: 'Font Size',
                subtitle: _appSettings.fontSizeName,
                onTap: () => _showFontSizeDialog(),
              ),

              _buildSection('Privacy & Links', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.link_rounded,
                title: 'Enable Links',
                subtitle: 'Allow clicking external links in messages',
                value: _appSettings.linksEnabled,
                onChanged: (v) => _appSettings.setLinksEnabled(v),
              ),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.security_outlined,
                title: 'Spam Protection',
                subtitle: 'Filter suspected spam messages',
                value: _spamProtection,
                onChanged: (v) {
                  setState(() => _spamProtection = v);
                  _saveBool('spam_protection', v);
                },
              ),

              _buildSection('About', sectionTextColor),
              _buildTappableTile(
                tileColor: tileColor,
                icon: Icons.info_outline,
                title: 'About SoftBridge Texts',
                subtitle: 'Version 1.0.0',
                onTap: () => _showAboutDialog(),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  void _showOtpTimerDialog() {
    int selected = _otpDeleteMinutes;
    final options = [1, 2, 5, 10, 15, 30, 60];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete OTP after', style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
        content: StatefulBuilder(builder: (ctx2, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((min) {
              return RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                title: Text('$min ${min == 1 ? 'minute' : 'minutes'}', style: GoogleFonts.openSans()),
                value: min,
                groupValue: selected,
                activeColor: const Color(0xFF0078D4),
                onChanged: (v) => setS(() => selected = v!),
              );
            }).toList(),
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() => _otpDeleteMinutes = selected);
              _saveInt('otp_delete_minutes', selected);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showFontSizeDialog() {
    String selected = _appSettings.fontSizeName;
    final options = ['Small', 'Medium', 'Large'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Font Size', style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
        content: StatefulBuilder(builder: (ctx2, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((size) {
              return RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(size, style: GoogleFonts.openSans()),
                value: size,
                groupValue: selected,
                activeColor: const Color(0xFF0078D4),
                onChanged: (v) => setS(() => selected = v!),
              );
            }).toList(),
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _appSettings.setFontSize(selected);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'SoftBridge Texts',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 SoftBridge Labs',
    );
  }

  Widget _buildSection(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildSwitchTile({required Color tileColor, required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(8)),
      child: SwitchListTile(
        secondary: Icon(icon, color: const Color(0xFF0078D4)),
        title: Text(title, style: GoogleFonts.openSans(fontWeight: FontWeight.w500, fontSize: 15)),
        subtitle: Text(subtitle, style: GoogleFonts.openSans(fontSize: 12, color: Colors.grey)),
        value: value,
        activeColor: const Color(0xFF0078D4),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildTappableTile({required Color tileColor, required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0078D4)),
        title: Text(title, style: GoogleFonts.openSans(fontWeight: FontWeight.w500, fontSize: 15)),
        subtitle: Text(subtitle, style: GoogleFonts.openSans(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

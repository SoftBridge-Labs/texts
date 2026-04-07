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
  bool _pinchToZoomEnabled = false;
  double _pinchZoomLevel = 1.0;
  bool _replySuggestionsEnabled = true;
  bool _emergencyAlertsEnabled = true;
  bool _scheduledMessagesEnabled = true;
  bool _readReceiptsEnabled = false;
  bool _screenshotProtection = false;
  bool _scanLinksEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled   = prefs.getBool('notifications_enabled') ?? true;
      _soundEnabled           = prefs.getBool('sound_enabled') ?? true;
      _vibrationEnabled       = prefs.getBool('vibration_enabled') ?? true;
      _otpAutoDelete          = prefs.getBool('otp_auto_delete_enabled') ?? true;
      _otpDeleteMinutes       = prefs.getInt('otp_delete_minutes') ?? 10;
      _spamProtection         = prefs.getBool('spam_protection') ?? true;
      _pinchToZoomEnabled     = prefs.getBool('pinch_to_zoom_enabled') ?? false;
      _pinchZoomLevel         = prefs.getDouble('pinch_zoom_level') ?? 1.0;
      _replySuggestionsEnabled = prefs.getBool('reply_suggestions_enabled') ?? true;
      _emergencyAlertsEnabled = prefs.getBool('emergency_alerts_enabled') ?? true;
      _scheduledMessagesEnabled = prefs.getBool('scheduled_messages_enabled') ?? true;
      _readReceiptsEnabled    = prefs.getBool('read_receipts_enabled') ?? false;
      _screenshotProtection   = prefs.getBool('screenshot_protection_enabled') ?? false;
      _scanLinksEnabled       = prefs.getBool('scan_links_enabled') ?? false;
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

  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
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
              // ── Notifications ────────────────────────────────────────────
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

              // ── OTP Messages ─────────────────────────────────────────────
              _buildSection('OTP Messages', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.timer_outlined,
                title: 'Auto-delete OTP messages',
                subtitle: 'Remove OTP SMS after a set time (checks on app open)',
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

              // ── Appearance ───────────────────────────────────────────────
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
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.pinch_outlined,
                title: 'Pinch to Zoom SMS',
                subtitle: 'Use two fingers to scale message text',
                value: _pinchToZoomEnabled,
                onChanged: (v) {
                  setState(() => _pinchToZoomEnabled = v);
                  _saveBool('pinch_to_zoom_enabled', v);
                  _appSettings.setPinchToZoom(v);
                },
              ),
              if (_pinchToZoomEnabled)
                _buildSliderTile(
                  tileColor: tileColor,
                  icon: Icons.zoom_in_outlined,
                  title: 'Message Zoom Level',
                  subtitle: '${_pinchZoomLevel.toStringAsFixed(1)}×',
                  value: _pinchZoomLevel,
                  min: 0.8,
                  max: 2.0,
                  onChanged: (v) {
                    setState(() => _pinchZoomLevel = v);
                    _saveDouble('pinch_zoom_level', v);
                    _appSettings.setPinchZoomLevel(v);
                  },
                ),

              // ── Smart Features ───────────────────────────────────────────
              _buildSection('Smart Features', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.chat_bubble_outline,
                title: 'Reply Suggestions',
                subtitle: 'Show smart reply buttons on messages',
                value: _replySuggestionsEnabled,
                onChanged: (v) {
                  setState(() => _replySuggestionsEnabled = v);
                  _saveBool('reply_suggestions_enabled', v);
                  _appSettings.setReplySuggestions(v);
                },
              ),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.schedule_outlined,
                title: 'Scheduled Messages',
                subtitle: 'Schedule SMS to be sent at a later time',
                value: _scheduledMessagesEnabled,
                onChanged: (v) {
                  setState(() => _scheduledMessagesEnabled = v);
                  _saveBool('scheduled_messages_enabled', v);
                },
              ),

              // ── Privacy & Links ─────────────────────────────────────────
              _buildSection('Privacy & Links', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.link_rounded,
                title: 'Enable Links',
                subtitle: 'Allow clicking external links in messages',
                value: _appSettings.linksEnabled,
                onChanged: (v) => _appSettings.setLinksEnabled(v),
              ),
              if (_appSettings.linksEnabled)
                _buildSwitchTile(
                  tileColor: tileColor,
                  icon: Icons.security_update_good_outlined,
                  title: 'Scan Links Before Opening',
                  subtitle: 'Check links for threats via SoftBridge security scan',
                  value: _scanLinksEnabled,
                  onChanged: (v) {
                    setState(() => _scanLinksEnabled = v);
                    _saveBool('scan_links_enabled', v);
                  },
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
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.done_all_outlined,
                title: 'Read Receipts',
                subtitle: 'Show when messages are read (where supported)',
                value: _readReceiptsEnabled,
                onChanged: (v) {
                  setState(() => _readReceiptsEnabled = v);
                  _saveBool('read_receipts_enabled', v);
                },
              ),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.screenshot_monitor_outlined,
                title: 'Screenshot Protection',
                subtitle: 'Block screenshots and screen recording in the app',
                value: _screenshotProtection,
                onChanged: (v) {
                  setState(() => _screenshotProtection = v);
                  _saveBool('screenshot_protection_enabled', v);
                },
              ),

              // ── Emergency Alerts ─────────────────────────────────────────
              _buildSection('Emergency Alerts', sectionTextColor),
              _buildSwitchTile(
                tileColor: tileColor,
                icon: Icons.warning_amber_outlined,
                title: 'Wireless Emergency Alerts',
                subtitle: 'Receive AMBER, Presidential & severe weather alerts',
                value: _emergencyAlertsEnabled,
                onChanged: (v) {
                  setState(() => _emergencyAlertsEnabled = v);
                  _saveBool('emergency_alerts_enabled', v);
                },
              ),

              // ── About ─────────────────────────────────────────────────────
              _buildSection('About', sectionTextColor),
              _buildTappableTile(
                tileColor: tileColor,
                icon: Icons.info_outline,
                title: 'About SoftBridge Texts',
                subtitle: 'Version 1.1.0',
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
      applicationVersion: '1.1.0',
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

  Widget _buildSliderTile({
    required Color tileColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0078D4)),
        title: Text(title, style: GoogleFonts.openSans(fontWeight: FontWeight.w500, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: GoogleFonts.openSans(fontSize: 12, color: Colors.grey)),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) / 0.1).round(),
              activeColor: const Color(0xFF0078D4),
              onChanged: onChanged,
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

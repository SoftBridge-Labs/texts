import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'message_list_screen.dart';

class PermissionStep {
  final String title;
  final String description;
  final IconData icon;
  final Permission permission;

  PermissionStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.permission,
  });
}

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  int _currentStepIndex = 0;

  final List<PermissionStep> _allSteps = [
    PermissionStep(
      title: 'SMS Access',
      description: 'SoftBridge Texts needs to read and send SMS to function as your messaging app.',
      icon: Icons.sms_outlined,
      permission: Permission.sms,
    ),
    PermissionStep(
      title: 'Contacts',
      description: 'This allows us to show names and photos for your conversations.',
      icon: Icons.contacts_outlined,
      permission: Permission.contacts,
    ),
    PermissionStep(
      title: 'Phone State',
      description: 'Required to manage message delivery and network status.',
      icon: Icons.phone_android_outlined,
      permission: Permission.phone,
    ),
    PermissionStep(
      title: 'Notifications',
      description: 'Get alerted immediately when you receive a new message.',
      icon: Icons.notifications_active_outlined,
      permission: Permission.notification,
    ),
  ];

  Future<void> _handlePermissionRequest() async {
    final currentStep = _allSteps[_currentStepIndex];
    final status = await currentStep.permission.request();
    
    if (status.isGranted || status.isLimited) {
      if (_currentStepIndex < _allSteps.length - 1) {
        setState(() {
          _currentStepIndex++;
        });
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('intro_seen', true);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MessageListScreen()),
          );
        }
      }
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable this permission in settings.')),
        );
        openAppSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _allSteps[_currentStepIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0078D4).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(step.icon, size: 64, color: const Color(0xFF0078D4)),
              ),
              const SizedBox(height: 48),
              Text(
                step.title,
                style: GoogleFonts.openSans(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                step.description,
                style: GoogleFonts.openSans(
                  fontSize: 16,
                  color: Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _allSteps.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentStepIndex
                          ? const Color(0xFF0078D4)
                          : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SInitialButton(
                onPressed: _handlePermissionRequest,
                text: _currentStepIndex == _allSteps.length - 1 ? 'Finish Setup' : 'Allow Access',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SInitialButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;

  const SInitialButton({super.key, required this.onPressed, required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0078D4),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(text, style: GoogleFonts.openSans(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

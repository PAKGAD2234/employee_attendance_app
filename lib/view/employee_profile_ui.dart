import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

// ─── Shared Theme Helpers ────────────────────────────────────────────────────

const kPrimaryBlue = Color(0xFF29B6F6);
const kDeepBlue = Color(0xFF0277BD);
const kBg = Colors.black;

/// Full-screen background: splash image + gradient overlay
class TimeTrackBackground extends StatelessWidget {
  final Widget child;
  const TimeTrackBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/splash.png', fit: BoxFit.cover),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xCC000000), Color(0xF5000000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Glassmorphism card
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double opacity;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.opacity = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opacity),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: child,
    );
  }
}

/// Glass text field
class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final IconData prefixIcon;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        prefixIcon: Icon(prefixIcon, color: kPrimaryBlue, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kPrimaryBlue, width: 1.5),
        ),
      ),
    );
  }
}

/// Gradient primary button
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryBlue, kDeepBlue],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: kPrimaryBlue.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Pulsing corner decoration widget
class _PulseCircle extends StatefulWidget {
  final double size;
  final Alignment alignment;
  const _PulseCircle({required this.size, required this.alignment});

  @override
  State<_PulseCircle> createState() => _PulseCircleState();
}

class _PulseCircleState extends State<_PulseCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _scale = Tween(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween(begin: 0.06, end: 0.14).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kPrimaryBlue, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Show a themed SnackBar
void showThemedSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFB71C1C) : kDeepBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
  );
}

// ─── Employee Profile Page ────────────────────────────────────────────────────

class EmployeeProfileUI extends StatefulWidget {
  final String employeeId;

  const EmployeeProfileUI({super.key, required this.employeeId});

  @override
  State<EmployeeProfileUI> createState() => _EmployeeProfileUIState();
}

class _EmployeeProfileUIState extends State<EmployeeProfileUI>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  bool isLoading = false;
  String fullName = 'Loading...';
  String englishName = '-';
  String username = '-';
  String phone = '-';
  String profilePhotoUrl = '';
  String storedPassword = '';
  String department = '-';
  String email = '-';

  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  
 

  @override

  void initState() {
    super.initState();
    supabaseService.initialize(supabase);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    loadEmployee();
  }

  Future<void> loadEmployee() async {
    try {
      final data = await supabaseService.getEmployee(widget.employeeId);
      if (mounted && data != null) {
        setState(() {
          fullName = data['full_name'] ?? 'Unknown';
          englishName = data['english_name'] ?? '-';
          username = data['username'] ?? '-';
          phone = data['phone'] ?? '-';
          department = data['department'] ?? '-';
          email = data['email'] ?? '-';

          profilePhotoUrl =
              supabaseService.getProfilePhotoUrl(data['profile_photo']);
          storedPassword = data['password'] ?? '';
        });
        _fadeCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) showThemedSnackBar(context, 'Error loading profile: $e', isError: true);
    }
  }

  Future<void> pickProfilePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await uploadProfilePhoto(bytes);
  }

  Future<void> uploadProfilePhoto(Uint8List bytes) async {
    setState(() => isLoading = true);
    try {
      final fileName =
          'profiles/${widget.employeeId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('attendance').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      await supabaseService.updateEmployee(widget.employeeId, {
        'profile_photo': fileName,
      });
      await loadEmployee();
      if (mounted) showThemedSnackBar(context, 'อัปโหลดรูปโปรไฟล์สำเร็จ');
    } catch (e) {
      if (mounted)
        showThemedSnackBar(context, 'Error uploading profile photo: $e',
            isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> changePassword() async {
    final current = currentPasswordController.text.trim();
    final newPw = newPasswordController.text.trim();
    final confirm = confirmPasswordController.text.trim();

    if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
      showThemedSnackBar(context, 'กรุณากรอกข้อมูลให้ครบ', isError: true);
      return;
    }
    if (newPw != confirm) {
      showThemedSnackBar(context, 'รหัสผ่านใหม่ไม่ตรงกัน', isError: true);
      return;
    }
    if (storedPassword.isNotEmpty && current != storedPassword) {
      showThemedSnackBar(context, 'รหัสผ่านปัจจุบันไม่ถูกต้อง', isError: true);
      return;
    }

    setState(() => isLoading = true);
    try {
      await supabaseService.changePassword(widget.employeeId, newPw);
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      if (mounted) showThemedSnackBar(context, 'เปลี่ยนรหัสผ่านสำเร็จ');
      await loadEmployee();
    } catch (e) {
      if (mounted)
        showThemedSnackBar(context, 'Error changing password: $e', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: TimeTrackBackground(
        child: Stack(
          children: [
            // ── Pulse corner decorations ──
            const _PulseCircle(size: 280, alignment: Alignment(-1.3, -1.1)),
            const _PulseCircle(size: 200, alignment: Alignment(1.4, 1.2)),

            // ── Main content ──
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      _buildCustomAppBar(),
                      Expanded(
                        child: isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: kPrimaryBlue,
                                ),
                              )
                            : _buildBody(),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Custom AppBar ─────────────────────────────────────────────────────────
  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          // Title
          const Text(
            'โปรไฟล์พนักงาน',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kPrimaryBlue, kDeepBlue],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'PROFILE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildAvatarSection(),
          const SizedBox(height: 20),
          _buildInfoCard(),
          const SizedBox(height: 20),
          _buildPasswordCard(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Avatar section ────────────────────────────────────────────────────────
  Widget _buildAvatarSection() {
    return Column(
      children: [
        // Pulsing ring around avatar
        _PulsingAvatarRing(
          child: CircleAvatar(
            radius: 52,
            backgroundColor: kDeepBlue.withOpacity(0.3),
            backgroundImage: profilePhotoUrl.isNotEmpty
                ? NetworkImage(profilePhotoUrl)
                : null,
            child: profilePhotoUrl.isEmpty
                ? const Icon(Icons.person, size: 56, color: kPrimaryBlue)
                : null,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          fullName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          department,
          style: TextStyle(
            color: kPrimaryBlue.withOpacity(0.85),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        // Change photo button (outlined style)
        OutlinedButton.icon(
          onPressed: pickProfilePhoto,
          icon: const Icon(Icons.photo_camera_outlined,
              size: 16, color: kPrimaryBlue),
          label: const Text('เปลี่ยนรูปโปรไฟล์',
              style: TextStyle(color: kPrimaryBlue, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kPrimaryBlue),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ),
      ],
    );
  }

  // ── Info card ─────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimaryBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_outlined,
                    color: kPrimaryBlue, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'ข้อมูลพนักงาน',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.alternate_email, 'Username', username),
          _buildInfoRow(Icons.mark_email_read_sharp, 'Email', email),
          _buildInfoRow(Icons.person_outline, 'ชื่อ', fullName),
          _buildInfoRow(Icons.language, 'ชื่ออังกฤษ', englishName),
          _buildInfoRow(Icons.phone, 'เบอร์โทรศัพท์', phone),
          _buildInfoRow(Icons.work, 'ตำแหน่ง', department),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(IconData icon, String title, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kPrimaryBlue.withOpacity(0.8), size: 18),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.isNotEmpty ? value : '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Divider(
                color: Colors.white.withOpacity(0.05),
                height: 1,
              )
            ],
          ),
        ),
      ],
    ),
  );
}

  // ── Password card ─────────────────────────────────────────────────────────
  Widget _buildPasswordCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimaryBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_outline,
                    color: kPrimaryBlue, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'เปลี่ยนรหัสผ่าน',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 12),
          GlassTextField(
            controller: currentPasswordController,
            label: 'รหัสผ่านปัจจุบัน',
            prefixIcon: Icons.lock_outline,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: newPasswordController,
            label: 'รหัสผ่านใหม่',
            prefixIcon: Icons.vpn_key_outlined,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: confirmPasswordController,
            label: 'ยืนยันรหัสผ่านใหม่',
            prefixIcon: Icons.check_circle_outline,
            obscureText: true,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'บันทึกรหัสผ่าน',
              icon: Icons.save_outlined,
              onPressed: changePassword,
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'v1.0.0 · TimeTrack',
        style: TextStyle(
          color: Colors.white.withOpacity(0.25),
          fontSize: 12,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── Pulsing Avatar Ring ───────────────────────────────────────────────────────
class _PulsingAvatarRing extends StatefulWidget {
  final Widget child;
  const _PulsingAvatarRing({required this.child});

  @override
  State<_PulsingAvatarRing> createState() => _PulsingAvatarRingState();
}

class _PulsingAvatarRingState extends State<_PulsingAvatarRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: kPrimaryBlue
                  .withOpacity(0.3 + 0.4 * _pulse.value),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: kPrimaryBlue
                    .withOpacity(0.1 + 0.2 * _pulse.value),
                blurRadius: 16 + 8 * _pulse.value,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
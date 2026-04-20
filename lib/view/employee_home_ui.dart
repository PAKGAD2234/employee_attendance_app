import 'package:employee_attendance_app/view/checkout_ui.dart';
import 'package:employee_attendance_app/view/employee_history_ui.dart';
import 'package:employee_attendance_app/view/employee_profile_ui.dart';
import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:employee_attendance_app/widgets/clock_widget.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'checkin_ui.dart';

class EmployeeHomeView extends StatefulWidget {
  final String employeeId;
  const EmployeeHomeView({super.key, required this.employeeId});

  @override
  State<EmployeeHomeView> createState() => _EmployeeHomeViewState();
}

class _EmployeeHomeViewState extends State<EmployeeHomeView>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  String fullName = '';
  String profilePhotoUrl = '';
  String status = 'ยังไม่ลงเวลา';
  bool isLoadingUser = true;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    supabaseService.initialize(supabase);
    loadUser();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> loadUser() async {
    final data = await supabaseService.getEmployee(widget.employeeId);
    if (!mounted) return;
    setState(() {
      fullName = data?['full_name'] ?? 'Unknown';
      profilePhotoUrl = supabaseService.getProfilePhotoUrl(
        data?['profile_photo'],
      );
      isLoadingUser = false;
    });
  }

  Future<void> logout() async {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Widget _actionButton({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55, // ลดจาก 72
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16), // ลดจาก 18
          border: filled
              ? null
              : Border.all(color: color.withOpacity(0.55), width: 1.5),
          gradient: filled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.75)],
                )
              : null,
          color: filled ? null : Colors.transparent,
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14), // ลดจาก 20
        child: Row(
          children: [
            Container(
              width: 20, // ลดจาก 42
              height: 20,
              decoration: BoxDecoration(
                color: filled
                    ? Colors.white.withOpacity(0.20)
                    : color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: filled ? Colors.white : color, size: 19), // ลดจาก 22
            ),
            const SizedBox(width: 12), // ลดจาก 16
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12, // ลดจาก 16
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : color,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 11, // ลดจาก 12
                      color: filled
                          ? Colors.white.withOpacity(0.70)
                          : color.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13, // ลดจาก 15
              color: filled
                  ? Colors.white.withOpacity(0.6)
                  : color.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background ──────────────────────────────────────────
          Image.asset('assets/images/splash.png', fit: BoxFit.cover),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x55000000),
                  Color(0xCC000000),
                  Color(0xF0000000),
                ],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),

          // ── Decor ───────────────────────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF29B6F6).withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // ── Main ────────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                    child: Row(
                      children: [
                        const Text(
                          'TimeTrack',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                              (route) => false,
                            );
                          },
                          child: Row(
                            children: [
                              // Logout button
                              Icon(
                                Icons.logout_rounded,
                                color: Colors.white.withOpacity(0.75),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ออกจากระบบ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.75),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Profile section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        // Avatar — ไม่อยู่ใน setState วินาที
                        ScaleTransition(
                          scale: _pulseAnim,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF29B6F6),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF29B6F6,
                                  ).withOpacity(0.40),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child:
                                  isLoadingUser
                                      ? Container(
                                        color: Colors.white.withOpacity(0.1),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF29B6F6),
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                      : profilePhotoUrl.isNotEmpty
                                      ? Image.network(
                                        profilePhotoUrl, // ✅ ไม่ต่อ timestamp แล้ว
                                        fit: BoxFit.cover,
                                        cacheWidth: 136,
                                        errorBuilder:
                                            (_, __, ___) => _defaultAvatar(),
                                      )
                                      : _defaultAvatar(),
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Name + status
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLoadingUser ? 'กำลังโหลด...' : fullName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.45),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      status,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ✅ ClockWidget แยก — ไม่ทำให้ parent rebuild
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: ClockWidget(),
                  ),

                  const SizedBox(height: 28),

                  // Action buttons
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 24, 32),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _actionButton(
                                  label: 'Check In',
                                  sublabel: 'บันทึกเวลาเข้างาน',
                                  icon: Icons.login_rounded,
                                  color: const Color(0xFF29B6F6),
                                  onTap:
                                      () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => CheckInUI(
                                                employeeId: widget.employeeId,
                                              ),
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _actionButton(
                                  label: 'Check Out',
                                  sublabel: 'บันทึกเวลาออกงาน',
                                  icon: Icons.logout_rounded,
                                  color: const Color(0xFF26C6DA),
                                  onTap:
                                      () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => CheckOutUI(
                                                employeeId: widget.employeeId,
                                              ),
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _actionButton(
                            label: 'โปรไฟล์',
                            sublabel: 'ดูและแก้ไขข้อมูลส่วนตัว',
                            icon: Icons.person_outline_rounded,
                            color: const Color(0xFF29B6F6),
                            filled: false,
                            onTap:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => EmployeeProfileUI(
                                          employeeId: widget.employeeId,
                                        ),
                                  ),
                                ).then((_) => loadUser()),
                          ),

                          const SizedBox(height: 12),

                          _actionButton(
                            label: 'ประวัติการลงเวลา',
                            sublabel: 'ดูรายการ Check In / Out ย้อนหลัง',
                            icon: Icons.history_rounded,
                            color: const Color(0xFF29B6F6),
                            filled: false,
                            onTap:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => EmployeeHistoryUI(
                                          employeeId: widget.employeeId,
                                        ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar() => Container(
    color: const Color(0xFF0277BD).withOpacity(0.5),
    child: const Icon(Icons.person_rounded, size: 36, color: Colors.white),
  );
}

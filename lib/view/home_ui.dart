import 'dart:ui';

import 'package:employee_attendance_app/view/landing_ui.dart';
import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:flutter/material.dart';

// ─── Stub imports — replace with your actual routes ───────────────────────────
// import 'package:employee_attendance_app/view/login_ui.dart';
// import 'package:employee_attendance_app/view/landing_ui.dart';

// ─── Minimal stubs so the file is self-contained for preview ──────────────────
class HomeUi extends StatelessWidget {
  const HomeUi({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('เข้าสู่ระบบ')),
        body: const Center(child: Text('Login Page')),
      );
}

// This is the LandingUi / TimeTrackApp you already have
class LandingUi extends StatelessWidget {
  const LandingUi({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('TimeTrack')),
        body: const Center(child: Text('Landing UI (TimeTrackApp)')),
      );
}

// ─── Entry point (for standalone testing) ─────────────────────────────────────
void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomepageUI(),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  HomepageUI
// ══════════════════════════════════════════════════════════════════════════════
class HomepageUI extends StatefulWidget {
  const HomepageUI({super.key});

  @override
  State<HomepageUI> createState() => _HomepageUIState();
}

class _HomepageUIState extends State<HomepageUI> with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;
  late final AnimationController _pulseCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideTitleAnim;
  late final Animation<Offset> _slideCardsAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 950))
      ..forward();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);

    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _slideTitleAnim = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _slideCardsAnim = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── helpers ────────────────────────────────────────────────────────────────
  void _goTo(Widget page) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Soft background gradient ───────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFEAF2FF),
                  Color(0xFFF5F8FF),
                  Color(0xFFE8F0FE),
                ],
              ),
            ),
          ),

          // ── Decorative blurred circles ─────────────────────────────────────
          Positioned(
            top: -80,
            left: -80,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: _GlowCircle(
                  size: 280,
                  color: const Color(0xFF29B6F6).withOpacity(0.12)),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: _GlowCircle(
                  size: 320,
                  color: const Color(0xFF1565C0).withOpacity(0.08)),
            ),
          ),
          Positioned(
            top: 160,
            right: -30,
            child: _GlowCircle(
                size: 140,
                color: const Color(0xFF29B6F6).withOpacity(0.07)),
          ),

          // ── Main content ───────────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // ── Logo + Title ──────────────────────────────────────────
                  Expanded(
                    flex: 4,
                    child: SlideTransition(
                      position: _slideTitleAnim,
                      child: _TitleSection(pulseAnim: _pulseAnim),
                    ),
                  ),

                  // ── Cards row ─────────────────────────────────────────────
                  Expanded(
                    flex: 5,
                    child: SlideTransition(
                      position: _slideCardsAnim,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            // ── Employee card ─────────────────────────────
                            Expanded(
                              child: _PortalCard(
                                icon: Icons.history_rounded,
                                iconColor: Colors.white,
                                iconBg: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF29B6F6),
                                    Color(0xFF1565C0),
                                  ],
                                ),
                                title: 'ลงเวลาเข้า-ออกงาน',
                                titleColor: const Color(0xFF1565C0),
                                description:
                                    'สำหรับพนักงาน\nลงเวลาเข้า-ออกงาน\nด้วยตำแหน่งที่ตั้ง',
                                buttonLabel: 'เข้าสู่ระบบ',
                                buttonFilled: true,
                                onPressed: () => _goTo(const LoginPage()),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // ── Admin card ────────────────────────────────
                            Expanded(
                              child: _PortalCard(
                                icon: Icons.admin_panel_settings_rounded,
                                iconColor: const Color(0xFF1976D2),
                                iconBg: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF1976D2).withOpacity(0.12),
                                    const Color(0xFF29B6F6).withOpacity(0.10),
                                  ],
                                ),
                                title: 'Admin Portal',
                                titleColor: const Color(0xFF1565C0),
                                description:
                                    'สำหรับผู้ดูแลระบบ\nจัดการข้อมูลพนักงาน\nและดูรายงาน',
                                buttonLabel: 'เข้าสู่ระบบผู้ดูแล',
                                buttonFilled: false,
                                onPressed: () => _goTo(const TimeTrackApp()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _TitleSection — Logo + "TimeTrack" + subtitle
// ══════════════════════════════════════════════════════════════════════════════
class _TitleSection extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _TitleSection({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Logo badge ─────────────────────────────────────────────────────────
ScaleTransition(
  scale: pulseAnim,
  child: Container(
    width: 100,
    height: 100,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.fromARGB(255, 23, 154, 248), Color.fromARGB(255, 245, 252, 255)],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color.fromARGB(255, 62, 156, 199).withOpacity(0.45),
          blurRadius: 32,
          spreadRadius: 2,
          offset: const Offset(0, 10),
        ),
      ],
      border: Border.all(
        color: const Color(0xFF29B6F6).withOpacity(0.5),
        width: 1.5,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),   // ← เพิ่ม padding รอบรูป
      child: Image.asset(
        'assets/images/OpMatch.png',
        fit: BoxFit.contain,
      ),
    ),
  ),
),
        const SizedBox(height: 20),

        // App name
        const Text(
          'TimeTrack',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0D1B3E),
            letterSpacing: 1.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),

        // Divider dot row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _hLine(),
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF29B6F6),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            _hLine(),
          ],
        ),
        const SizedBox(height: 8),

        Text(
          'ระบบลงเวลาพนักงาน',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0D1B3E).withOpacity(0.5),
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _hLine() => Container(
        width: 34,
        height: 2,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B3E).withOpacity(0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  _PortalCard — reusable employee / admin card
// ══════════════════════════════════════════════════════════════════════════════
class _PortalCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final LinearGradient iconBg;
  final String title;
  final Color titleColor;
  final String description;
  final String buttonLabel;
  final bool buttonFilled;
  final VoidCallback onPressed;

  const _PortalCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.titleColor,
    required this.description,
    required this.buttonLabel,
    required this.buttonFilled,
    required this.onPressed,
  });

  @override
  State<_PortalCard> createState() => _PortalCardState();
}

class _PortalCardState extends State<_PortalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scale(_hovered ? 1.025 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0)
                  .withOpacity(_hovered ? 0.14 : 0.07),
              blurRadius: _hovered ? 32 : 20,
              spreadRadius: _hovered ? 2 : 0,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: _hovered
                ? const Color(0xFF29B6F6).withOpacity(0.35)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Icon ──────────────────────────────────────────────────
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: widget.iconBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF29B6F6).withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 32),
              ),

              // ── Title ─────────────────────────────────────────────────
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: widget.titleColor,
                  height: 1.3,
                ),
              ),

              // ── Description ───────────────────────────────────────────
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: const Color(0xFF0D1B3E).withOpacity(0.48),
                  fontWeight: FontWeight.w400,
                ),
              ),

              // ── Button ────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 46,
                child: widget.buttonFilled
                    ? ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          widget.buttonLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: widget.onPressed,
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Color(0xFF1976D2),
                        ),
                        label: Text(
                          widget.buttonLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1976D2),
                            letterSpacing: 0.2,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xFF1976D2), width: 1.5),
                          backgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: widget.onPressed,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _GlowCircle — decorative background circle
// ══════════════════════════════════════════════════════════════════════════════
class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
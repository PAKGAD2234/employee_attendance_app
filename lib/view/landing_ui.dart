import 'dart:math' as math;
import 'dart:ui';

import 'package:employee_attendance_app/view/company_login_page.dart';
import 'package:employee_attendance_app/view/home_ui.dart';
import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:flutter/material.dart';

void main() => runApp(const TimeTrackApp());

class TimeTrackApp extends StatelessWidget {
  const TimeTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TimeTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Sarabun',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A6FE8)),
        useMaterial3: true,
      ),
      home: const LandingUi(),
    );
  }
}

class LandingUi extends StatefulWidget {
  const LandingUi({super.key});

  @override
  State<LandingUi> createState() => _LandingUiState();
}

class _LandingUiState extends State<LandingUi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.07),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AnimatedBackground(),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xCC0A1628),
                  Color(0xBB0D2954),
                  Color(0x991A6FE8),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 40),
                    child: FadeTransition(
                      opacity: _fadeIn,
                      child: SlideTransition(
                        position: _slideUp,
                        child: const _ContentCard(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 16,
                  child: IconButton(
                    onPressed: () {
                      Navigator.maybePop(context).then((popped) {
                        if (!popped) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HomepageUI()),
                          );
                        }
                      });
                    },
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      backgroundColor: Colors.white.withOpacity(0.12),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated background (เหมือนเดิม) ──────────────────────
class _AnimatedBackground extends StatefulWidget {
  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(painter: _OrbPainter(_ctrl.value)),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  _OrbPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final orbs = [
      _Orb(size.width * 0.15 + math.sin(t * math.pi * 2) * 60,
          size.height * 0.25 + math.cos(t * math.pi * 2) * 40,
          260, const Color(0x221A6FE8)),
      _Orb(size.width * 0.85 + math.cos(t * math.pi * 2 + 1) * 50,
          size.height * 0.7 + math.sin(t * math.pi * 2 + 1) * 60,
          320, const Color(0x1A0EA5E9)),
      _Orb(size.width * 0.5 + math.sin(t * math.pi * 2 + 2) * 80,
          size.height * 0.85 + math.cos(t * math.pi * 2 + 2) * 30,
          200, const Color(0x186366F1)),
    ];
    for (final o in orbs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [o.color, Colors.transparent],
        ).createShader(
            Rect.fromCircle(center: Offset(o.x, o.y), radius: o.r));
      canvas.drawCircle(Offset(o.x, o.y), o.r, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}

class _Orb {
  final double x, y, r;
  final Color color;
  const _Orb(this.x, this.y, this.r, this.color);
}

// ── Glass card (ลดลงเหลือ 2 ปุ่ม) ────────────────────────
class _ContentCard extends StatelessWidget {
  const _ContentCard();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cardWidth = w > 700 ? 480.0 : double.infinity;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: cardWidth,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: Colors.white.withOpacity(0.18), width: 1.2),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF1A6FE8).withOpacity(0.25),
                    blurRadius: 60,
                    spreadRadius: -10,
                    offset: const Offset(0, 20)),
                BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 40,
                    offset: const Offset(0, 10)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(32, 44, 32, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LogoSection(),
                const SizedBox(height: 32),
                _Divider(),
                const SizedBox(height: 28),

                // ── ปุ่มเลือกบริษัท ──
                _MenuButton(
                  icon: Icons.business_rounded,
                  label: 'เข้าสู่ระบบบริษัท',
                  subtitle: 'สำหรับบริษัททุกสาขา',
                  accent: const Color(0xFF1A6FE8),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      // ส่ง workSite เป็น null / empty → CompanyLoginPage จัดการเอง
                      builder: (_) => CompanyLoginPage(workSite: const {}),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── ปุ่ม Admin ──
                _MenuButton(
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'เข้าสู่ระบบผู้ดูแล',
                  subtitle: 'Admin Panel',
                  accent: const Color(0xFF6366F1),
                  outlined: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Logo section (เหมือนเดิม) ──────────────────────────────
 // ใน _LogoSection ของ landing_ui.dart
class _LogoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo — เหมือน splash
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1565C0),
                Color.fromARGB(255, 207, 215, 219),
                Color.fromARGB(255, 184, 226, 245),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29B6F6).withOpacity(0.50),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: const Color(0xFF29B6F6).withOpacity(0.60),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Image.asset(
              'assets/images/OpMatch.png',
              fit: BoxFit.contain,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // App name
        const Text(
          'TimeTrack',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.2,
            height: 1.1,
          ),
        ),

        const SizedBox(height: 8),

        // Divider accent — เหมือน splash
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32, height: 2,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF29B6F6),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 32, height: 2,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Subtitle badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF29B6F6).withOpacity(0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: const Color(0xFF29B6F6).withOpacity(0.4), width: 1),
          ),
          child: Text(
            'ระบบลงเวลาพนักงาน',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.80),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}


class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Container(
                height: 1,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                  Colors.transparent,
                  Colors.white.withOpacity(0.2)
                ])))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.fiber_manual_record,
              size: 6, color: Colors.white.withOpacity(0.3)),
        ),
        Expanded(
            child: Container(
                height: 1,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                  Colors.white.withOpacity(0.2),
                  Colors.transparent
                ])))),
      ],
    );
  }
}

// ── ปุ่มเมนูใหม่ ────────────────────────────────────────────
class _MenuButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accent;
  final bool outlined;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.outlined = false,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_hovered ? 1.025 : 1.0),
          transformAlignment: Alignment.center,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: widget.outlined
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accent.withOpacity(_hovered ? 0.95 : 0.85),
                      widget.accent.withOpacity(_hovered ? 0.75 : 0.6),
                    ],
                  ),
            color: widget.outlined
                ? Colors.white.withOpacity(_hovered ? 0.08 : 0.03)
                : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.outlined
                  ? Colors.white.withOpacity(_hovered ? 0.5 : 0.25)
                  : widget.accent.withOpacity(_hovered ? 0.0 : 0.3),
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: widget.accent.withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: widget.outlined
                      ? widget.accent.withOpacity(0.15)
                      : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    Text(widget.subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.6))),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform:
                    Matrix4.translationValues(_hovered ? 4 : 0, 0, 0),
                child: Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.7), size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
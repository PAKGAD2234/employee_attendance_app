import 'package:employee_attendance_app/view/admin_ui.dart';
import 'package:flutter/material.dart';
import 'employee_home_ui.dart';
import 'login_ui.dart';

class HomepageUI extends StatefulWidget {
  const HomepageUI({super.key});

  @override
  State<HomepageUI> createState() => _HomepageUIState();
}

class _HomepageUIState extends State<HomepageUI>
    with TickerProviderStateMixin {

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideTitleAnim;
  late Animation<Offset> _slideButtonAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _slideTitleAnim = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _slideButtonAnim = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _pulseAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background image ──────────────────────────────────────
          Image.asset(
            'assets/images/splash.png',
            fit: BoxFit.cover,
          ),

          // ── Gradient overlay ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x44000000),
                  Color(0xBB000000),
                  Color(0xF2000000),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── Decorative circles ────────────────────────────────────
          Positioned(
            top: -70,
            left: -70,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                    width: 1.5,
                  ),
                  color: Colors.white.withOpacity(0.03),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: -40,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF29B6F6).withOpacity(0.20),
                    width: 1,
                  ),
                  color: const Color(0xFF29B6F6).withOpacity(0.05),
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── Top: Logo + Title ────────────────────────────────
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideTitleAnim,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon badge
                          ScaleTransition(
                            scale: _pulseAnim,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF29B6F6),
                                    Color(0xFF0277BD),
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
                              ),
                              child: const Icon(
                                Icons.access_time_rounded,
                                size: 58,
                                color: Colors.white,
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // App name
                          const Text(
                            'TimeTrack',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.5,
                              height: 1.1,
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Divider row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 36,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF29B6F6),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 36,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'ระบบลงเวลาพนักงาน',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.75),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Bottom: Buttons ──────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideButtonAnim,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
                      child: Column(
                        children: [
                          // Employee login button
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.login_rounded, size: 22),
                              label: const Text(
                                'เข้าสู่ระบบ',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF29B6F6),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ).copyWith(
                                overlayColor: WidgetStateProperty.all(
                                  Colors.white.withOpacity(0.15),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginPage(),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Admin button — outlined glass style
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                Icons.shield_rounded,
                                size: 22,
                                color: Color(0xFF29B6F6),
                              ),
                              label: const Text(
                                'Admin Portal',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF29B6F6),
                                  width: 1.5,
                                ),
                                backgroundColor: Colors.white.withOpacity(0.07),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginPage(),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 28),

                        
                         
                        ],
                      ),
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
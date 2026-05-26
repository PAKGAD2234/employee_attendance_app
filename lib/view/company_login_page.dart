import 'package:employee_attendance_app/view/company_dashboard_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class CompanyLoginPage extends StatefulWidget {
  final Map<String, dynamic> workSite;

  const CompanyLoginPage({super.key, required this.workSite});

  @override
  State<CompanyLoginPage> createState() => _CompanyLoginPageState();
}

class _CompanyLoginPageState extends State<CompanyLoginPage>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  final _pinCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMsg;

  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    supabaseService.initialize(supabase);

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ── Login: ค้นหาบริษัทจาก PIN ─────────────────────────────
  Future<void> _login() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMsg = 'กรุณากรอก PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      // ค้นหา work_site ที่มี PIN ตรงกัน
      final res = await supabase
          .from('work_sites')
          .select('id, name, address, pin')
          .eq('pin', pin)
          .maybeSingle();

      if (res != null) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CompanyDashboardView(workSite: res),
            ),
          );
        }
      } else {
        setState(() => _errorMsg = 'PIN ไม่ถูกต้อง');
      }
    } catch (e) {
      setState(() => _errorMsg = 'เกิดข้อผิดพลาด: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E1B4B),
                  Color(0xFF312E81),
                  Color(0xFF4338CA),
                ],
              ),
            ),
          ),

          // Pulse circles
          Positioned(
            top: -80, right: -80,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 240, height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.1), width: 1.5),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60, left: -60,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Back button
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Logo badge
                        ScaleTransition(
                          scale: _pulseAnim,
                          child: Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4F46E5).withOpacity(0.5),
                                  blurRadius: 32, spreadRadius: 2,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1.5),
                            ),
                            child: const Icon(Icons.business_rounded,
                                color: Colors.white, size: 42),
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text('เข้าระบบพนักงาน',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        Text(
                          'กรอก PIN ของบริษัท/สาขาคุณ',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.55)),
                        ),
                        const SizedBox(height: 36),

                        // Card
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.14), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Error
                              if (_errorMsg != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: Colors.redAccent, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_errorMsg!,
                                            style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 13)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              Text('PIN บริษัท',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withOpacity(0.7))),
                              const SizedBox(height: 10),

                              // PIN field
                              TextField(
                                controller: _pinCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                obscureText: true,
                                autofocus: true,
                                onSubmitted: (_) => _login(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  letterSpacing: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: '● ● ● ● ● ●',
                                  hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.25),
                                      fontSize: 18,
                                      letterSpacing: 8),
                                  counterText: '',
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF818CF8), size: 20),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.08),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.15),
                                        width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF818CF8), width: 1.8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 18),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('PIN 6 หลักที่ได้รับจาก Admin',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.35))),

                              const SizedBox(height: 28),

                              // Submit button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        const Color(0xFF6366F1).withOpacity(0.5),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22, height: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5))
                                      : const Text('เข้าสู่ระบบ',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
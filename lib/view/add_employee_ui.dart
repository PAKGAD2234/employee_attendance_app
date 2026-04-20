import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class AddEmployeeUI extends StatefulWidget {
  const AddEmployeeUI({super.key});

  @override
  State<AddEmployeeUI> createState() => _AddEmployeeUIState();
}

class _AddEmployeeUIState extends State<AddEmployeeUI>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  final fullNameController = TextEditingController();
  final englishNameController = TextEditingController();
  final phoneController = TextEditingController();
  final departmentController = TextEditingController();

  bool isLoading = false;
  String? generatedUsername;
  String? generatedPassword;
  String? generatedEmployeeCode;

  late AnimationController _fadeController;
  late AnimationController _resultSlideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _resultSlideAnim;

  @override
  void initState() {
    super.initState();
    supabaseService.initialize(supabase);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _resultSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _resultSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resultSlideController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _resultSlideController.dispose();
    fullNameController.dispose();
    englishNameController.dispose();
    phoneController.dispose();
    departmentController.dispose();
    super.dispose();
  }

  Future<void> createNewEmployee() async {
    if (fullNameController.text.isEmpty ||
        phoneController.text.isEmpty ||
        departmentController.text.isEmpty) {
      _showSnackBar("กรุณากรอกข้อมูลให้ครบ", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await supabaseService.createEmployee(
        fullName: fullNameController.text,
        englishName: englishNameController.text,
        phone: phoneController.text,
        department: departmentController.text,
      );

      if (result['success'] == true) {
        setState(() {
          generatedUsername = result['username'];
          generatedPassword = result['password'];
          generatedEmployeeCode = result['employee']?['employee_code'] ?? '-';
        });

        _resultSlideController.forward(from: 0);
        _showSnackBar(result['message'] ?? "สร้างพนักงานสำเร็จ");
      }
    } catch (e) {
      if (mounted) _showSnackBar("Error: $e", isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red.shade700 : const Color(0xFF0277BD),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar("คัดลอก $label แล้ว");
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white.withOpacity(0.50),
          letterSpacing: 0.5,
        ),
      );

  Widget _glassField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF29B6F6), size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.13), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF29B6F6), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _credentialTile({
    required String label,
    required String value,
    required IconData icon,
    Color accentColor = const Color(0xFF29B6F6),
    bool canCopy = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.45),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          if (canCopy)
            GestureDetector(
              onTap: () => copyToClipboard(value, label),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.copy_rounded, color: accentColor, size: 17),
              ),
            ),
        ],
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
                  Color(0xF2000000),
                ],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // ── Decor circles ───────────────────────────────────────
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF29B6F6).withOpacity(0.15),
                  width: 1.5,
                ),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // AppBar replacement
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'เพิ่มพนักงาน',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF29B6F6).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF29B6F6).withOpacity(0.40),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.person_add_rounded,
                                color: Color(0xFF29B6F6), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'New Employee',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF29B6F6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable body
                Expanded(
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF29B6F6),
                            strokeWidth: 2.5,
                          ),
                        )
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Form card ────────────────────
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.12),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF29B6F6)
                                                  .withOpacity(0.18),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                              Icons.badge_rounded,
                                              color: Color(0xFF29B6F6),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'ข้อมูลพนักงาน',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 22),

                                      _sectionLabel('ชื่อ - สกุล (ภาษาไทย) *'),
                                      const SizedBox(height: 8),
                                      _glassField(
                                        controller: fullNameController,
                                        hint: 'เช่น สมชาย สมิทธิ์',
                                        icon: Icons.person_outline_rounded,
                                      ),

                                      const SizedBox(height: 16),

                                      _sectionLabel('ชื่อภาษาอังกฤษ'),
                                      const SizedBox(height: 8),
                                      _glassField(
                                        controller: englishNameController,
                                        hint: 'เช่น Somchai Smith',
                                        icon: Icons.translate_rounded,
                                      ),

                                      const SizedBox(height: 16),

                                      _sectionLabel('เบอร์โทรศัพท์ *'),
                                      const SizedBox(height: 8),
                                      _glassField(
                                        controller: phoneController,
                                        hint: 'เช่น 0812345678',
                                        icon: Icons.phone_outlined,
                                        keyboardType: TextInputType.phone,
                                      ),

                                      const SizedBox(height: 16),

                                      _sectionLabel('แผนก *'),
                                      const SizedBox(height: 8),
                                      _glassField(
                                        controller: departmentController,
                                        hint: 'เช่น ฝ่ายขาย, ฝ่ายการเงิน',
                                        icon: Icons.business_outlined,
                                      ),

                                      const SizedBox(height: 24),

                                      SizedBox(
                                        width: double.infinity,
                                        height: 54,
                                        child: ElevatedButton.icon(
                                          icon: const Icon(
                                              Icons.person_add_rounded,
                                              size: 20),
                                          label: const Text(
                                            'สร้างพนักงาน',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF29B6F6),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: createNewEmployee,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Result card ───────────────────
                                if (generatedUsername != null) ...[
                                  const SizedBox(height: 20),
                                  SlideTransition(
                                    position: _resultSlideAnim,
                                    child: FadeTransition(
                                      opacity: _fadeAnim,
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(22),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.08),
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                            color: const Color(0xFF29B6F6)
                                                .withOpacity(0.30),
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                            0xFF29B6F6)
                                                        .withOpacity(0.18),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Icon(
                                                    Icons.key_rounded,
                                                    color: Color(0xFF29B6F6),
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                const Text(
                                                  'ข้อมูล Login พนักงาน',
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(height: 18),

                                            _credentialTile(
                                              label: 'รหัสพนักงาน',
                                              value: generatedEmployeeCode ?? '-',
                                              icon: Icons.badge_outlined,
                                              canCopy: false,
                                            ),

                                            const SizedBox(height: 10),

                                            _credentialTile(
                                              label: 'ชื่อผู้ใช้ (Username)',
                                              value: generatedUsername ?? '-',
                                              icon: Icons.person_outline_rounded,
                                            ),

                                            const SizedBox(height: 10),

                                            _credentialTile(
                                              label: 'รหัสผ่าน (Password)',
                                              value: generatedPassword ?? '-',
                                              icon: Icons.lock_outline_rounded,
                                              accentColor: const Color(0xFFEF5350),
                                            ),

                                            const SizedBox(height: 16),

                                            // Warning banner
                                            Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: Colors.orange
                                                    .withOpacity(0.10),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.orange
                                                      .withOpacity(0.45),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.info_outline_rounded,
                                                    color: Colors.orange,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      'เก็บข้อมูลนี้ไว้ให้พนักงาน พนักงานสามารถเปลี่ยนรหัสผ่านได้ภายหลัง',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.orange
                                                            .withOpacity(0.90),
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
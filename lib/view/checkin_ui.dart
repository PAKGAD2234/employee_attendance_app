import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class CheckInUI extends StatefulWidget {
  final String employeeId;
  const CheckInUI({super.key, required this.employeeId});

  @override
  State<CheckInUI> createState() => _CheckInUIState();
}

class _CheckInUIState extends State<CheckInUI>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  File? imageFile;
  bool isLoading = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => imageFile = File(picked.path));
    }
  }

  Future<Position> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> checkIn() async {
    if (imageFile == null) {
      _showSnackBar('กรุณาถ่ายรูปก่อน', isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final pos = await getLocation();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('attendance').upload(fileName, imageFile!);

      await supabase.from('attendance').insert({
        'employee_id': widget.employeeId,
        'work_date': DateTime.now().toIso8601String().split('T')[0],
        'checkin_time': DateTime.now().toIso8601String(),
        'checkin_lat': pos.latitude,
        'checkin_lng': pos.longitude,
        'checkin_photo': fileName,
        'status': 'checkin',
      }).select();

      _showSnackBar('เช็คอินสำเร็จ ✓');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    }

    setState(() => isLoading = false);
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red.shade700 : const Color(0xFF0277BD),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(DateTime dt) {
    const thDays = ['จันทร์','อังคาร','พุธ','พฤหัส','ศุกร์','เสาร์','อาทิตย์'];
    const thMonths = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                      'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
    return 'วัน${thDays[dt.weekday - 1]}ที่ ${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

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
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF29B6F6).withOpacity(0.12),
                  width: 1.5,
                ),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // AppBar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          'Check In',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF29B6F6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFF29B6F6).withOpacity(0.40)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.login_rounded,
                                  color: Color(0xFF29B6F6), size: 14),
                              SizedBox(width: 5),
                              Text('เข้างาน',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF29B6F6),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      child: Column(
                        children: [
                          // ── Date / Time card ────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 18, horizontal: 22),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.12)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _formatTime(now),
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(now),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.50),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── Photo area ──────────────────────────
                          GestureDetector(
                            onTap: isLoading ? null : pickImage,
                            child: Container(
                              height: 260,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: imageFile != null
                                      ? const Color(0xFF29B6F6).withOpacity(0.55)
                                      : Colors.white.withOpacity(0.12),
                                  width: imageFile != null ? 1.5 : 1,
                                ),
                              ),
                              child: imageFile == null
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 72,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF29B6F6)
                                                .withOpacity(0.15),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF29B6F6)
                                                  .withOpacity(0.35),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt_rounded,
                                            color: Color(0xFF29B6F6),
                                            size: 32,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        const Text(
                                          'แตะเพื่อถ่ายรูป',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF29B6F6),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'จำเป็นต้องถ่ายรูปก่อนเช็คอิน',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Colors.white.withOpacity(0.35),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(21),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.file(imageFile!,
                                              fit: BoxFit.cover),
                                          // retake overlay
                                          Positioned(
                                            bottom: 12,
                                            right: 12,
                                            child: GestureDetector(
                                              onTap: pickImage,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withOpacity(0.60),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                      color: Colors.white
                                                          .withOpacity(0.25)),
                                                ),
                                                child: const Row(
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .camera_alt_rounded,
                                                        color: Colors.white,
                                                        size: 15),
                                                    SizedBox(width: 6),
                                                    Text('ถ่ายใหม่',
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ── Location note ───────────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.10)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    color:
                                        Colors.white.withOpacity(0.45),
                                    size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'ระบบจะบันทึกพิกัดอัตโนมัติเมื่อเช็คอิน',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.40),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Submit button ───────────────────────
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : const Icon(Icons.check_circle_rounded,
                                      size: 22),
                              label: Text(
                                isLoading ? 'กำลังบันทึก...' : 'ยืนยัน Check In',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: imageFile != null
                                    ? const Color(0xFF29B6F6)
                                    : Colors.white.withOpacity(0.15),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: isLoading ? null : checkIn,
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
}
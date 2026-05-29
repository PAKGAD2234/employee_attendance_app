import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // ← kIsWeb อยู่ที่นี่
// ─────────────────────────────────────────────────────────────────────────────
// CheckOutUI
// ─────────────────────────────────────────────────────────────────────────────
class CheckOutUI extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String employeePhone;

  const CheckOutUI({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.employeePhone,
  });

  @override
  State<CheckOutUI> createState() => _CheckOutUIState();
}

class _CheckOutUIState extends State<CheckOutUI>
    with SingleTickerProviderStateMixin {
  // ── Services ─────────────────────────────────────────────────────────────
  final _supabase = Supabase.instance.client;

  // ── UI state ──────────────────────────────────────────────────────────────
  XFile? _imageFile;
  Uint8List? _imageBytes;
  bool _isSubmitting = false;

  // ── Live clock ────────────────────────────────────────────────────────────
  late DateTime _now;
  Timer? _clockTimer;

  // ── Fade animation ────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── GPS state for recording checkout location ─────────────────────────────
  /// null = not yet fetched; Position once obtained
  Position? _checkoutPos;
  bool _fetchingPos = false;

  // Check-in time display (fetched on load for reference)
  String? _checkInTimeDisplay;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _fadeCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
          ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _loadCheckInInfo();
    _prefetchLocation();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pre-fetch today's check-in info & location
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadCheckInInfo() async {
    try {
      final today = _dateStr(DateTime.now().toLocal());
      final rows = await _supabase
          .from('attendance')
          .select('checkin_time')
          .eq('employee_id', widget.employeeId)
          .eq('work_date', today)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        final ci = rows[0]['checkin_time'] as String?;
        if (ci != null) {
          final dt = DateTime.parse(ci).toLocal();
          setState(() => _checkInTimeDisplay =
              'เช็คอินเวลา ${_timeStr(dt)}');
        }
      }
    } catch (_) {}
  }

  Future<void> _prefetchLocation() async {
    setState(() => _fetchingPos = true);
    try {
      final pos = await _ensureLocationAndGet();
      if (mounted) setState(() => _checkoutPos = pos);
    } catch (_) {
      // Will retry on submit
    } finally {
      if (mounted) setState(() => _fetchingPos = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GPS Permission Helper (identical to CheckIn)
  // ─────────────────────────────────────────────────────────────────────────

   Future<Position> _ensureLocationAndGet() async {
  if (kIsWeb) {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('GPS ปิดอยู่ กรุณาเปิดตำแหน่งในการตั้งค่า');
  }
  final status = await Permission.locationWhenInUse.request();
  if (status.isPermanentlyDenied) {
    throw Exception('ถูกปฏิเสธ GPS ถาวร ไปที่ การตั้งค่า → แอป → อนุญาตตำแหน่ง');
  }
  if (status.isDenied) {
    throw Exception('ต้องการสิทธิ์ GPS เพื่อเช็คเอาท์');
  }
  return Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
    timeLimit: const Duration(seconds: 15),
  );
}

  // ─────────────────────────────────────────────────────────────────────────
  // Photo
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) {
      setState(() {
        _imageFile = picked;
        _imageBytes = bytes;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Check-out submission
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _submitCheckOut() async {
    if (_imageFile == null) {
      _snack('กรุณาถ่ายรูปก่อน', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final now = DateTime.now().toLocal();
      final today = _dateStr(now);

      // ── Get GPS (use pre-fetched if available, else re-fetch) ──────────
      Position pos;
      try {
        pos = _checkoutPos ?? await _ensureLocationAndGet();
      } catch (e) {
        _snack('ไม่สามารถดึงตำแหน่งได้: $e', isError: true);
        setState(() => _isSubmitting = false);
        return;
      }

      // ── Verify today's check-in record exists ──────────────────────────
      final rows = await _supabase
          .from('attendance')
          .select('id, checkout_time')
          .eq('employee_id', widget.employeeId)
          .eq('work_date', today)
          .limit(1);

      if (rows.isEmpty) {
        _snack('ไม่พบข้อมูล Check In วันนี้', isError: true);
        setState(() => _isSubmitting = false);
        return;
      }
      if (rows[0]['checkout_time'] != null) {
        _snack('เช็คเอาท์วันนี้ไปแล้ว', isError: true);
        setState(() => _isSubmitting = false);
        return;
      }

      // ── Upload photo ───────────────────────────────────────────────────
      final fileName = '${now.millisecondsSinceEpoch}_out.jpg';
      final bytes = await _imageFile!.readAsBytes();
      await _supabase.storage.from('attendance').uploadBinary(fileName, bytes);

      // ── Update attendance record ───────────────────────────────────────
      final updated = await _supabase
          .from('attendance')
          .update({
            'checkout_time': now.toIso8601String(),
            'checkout_photo': fileName,
            'checkout_lat': pos.latitude,
            'checkout_lng': pos.longitude,
            'status': 'checkout',
          })
          .eq('employee_id', widget.employeeId)
          .eq('work_date', today)
          .filter('checkout_time', 'is', null)
          .select();

      if (updated.isEmpty) {
        _snack('ไม่สามารถบันทึกข้อมูลได้ กรุณาลองใหม่', isError: true);
        setState(() => _isSubmitting = false);
        return;
      }

      // Optional push notification
      try {
        await _supabase.functions.invoke('push-notify', body: {
          'title': '🔚 เช็คเอาท์แล้ว',
          'body': '${widget.employeeName} • ${_timeStr(now)}',
        });
      } catch (_) {}

      _snack('เช็คเอาท์สำเร็จ ✓');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('เกิดข้อผิดพลาด: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Formatters
  // ─────────────────────────────────────────────────────────────────────────

  String _timeStr(DateTime dt) =>
      '${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';

  String _dateStr(DateTime dt) =>
      '${dt.year}-${_p(dt.month)}-${_p(dt.day)}';

  String _p(int n) => n.toString().padLeft(2, '0');

  String _thaiDate(DateTime dt) {
    const days = ['จันทร์','อังคาร','พุธ','พฤหัส','ศุกร์','เสาร์','อาทิตย์'];
    const months = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                    'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
    return 'วัน${days[dt.weekday - 1]}ที่ ${dt.day} ${months[dt.month - 1]} ${dt.year + 543}';
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : const Color(0xFFF57C00),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  static const _accent = Color(0xFFFFB74D); // amber — checkout theme

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/splash.png', fit: BoxFit.cover),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55000000), Color(0xCC000000), Color(0xF0000000)],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _accent.withOpacity(0.12), width: 1.5),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      child: Column(
                        children: [
                          _buildClockCard(),
                          const SizedBox(height: 20),
                          _buildPhotoArea(),
                          const SizedBox(height: 14),
                          _buildGpsInfoCard(),
                          const SizedBox(height: 28),
                          _buildSubmitButton(),
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

  // ── AppBar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        const Text('Check Out',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                color: Colors.white)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accent.withOpacity(0.40)),
          ),
          child: Row(children: [
            Icon(Icons.logout_rounded, color: _accent, size: 14),
            const SizedBox(width: 5),
            Text('ออกงาน',
                style: TextStyle(fontSize: 12, color: _accent,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  // ── Clock card ────────────────────────────────────────────────────────────

  Widget _buildClockCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(children: [
        Text(_timeStr(_now),
            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800,
                color: Colors.white, letterSpacing: 3)),
        const SizedBox(height: 4),
        Text(_thaiDate(_now),
            style: TextStyle(fontSize: 13,
                color: Colors.white.withOpacity(0.50))),
        if (_checkInTimeDisplay != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _checkInTimeDisplay!,
              style: TextStyle(fontSize: 12, color: _accent,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Photo area ────────────────────────────────────────────────────────────

  Widget _buildPhotoArea() {
    return GestureDetector(
      onTap: _isSubmitting ? null : _pickImage,
      child: Container(
        height: 240,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _imageFile != null
                ? _accent.withOpacity(0.55)
                : Colors.white.withOpacity(0.12),
            width: _imageFile != null ? 1.5 : 1,
          ),
        ),
        child: _imageFile == null ? _photoPlaceholder() : _photoPreview(),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: _accent.withOpacity(0.35), width: 1.5),
        ),
        child: Icon(Icons.camera_alt_rounded, color: _accent, size: 32),
      ),
      const SizedBox(height: 14),
      Text('แตะเพื่อถ่ายรูป',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: _accent)),
      const SizedBox(height: 4),
      Text('จำเป็นต้องถ่ายรูปก่อนเช็คเอาท์',
          style: TextStyle(fontSize: 12,
              color: Colors.white.withOpacity(0.35))),
    ]);
  }

  Widget _photoPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: Stack(fit: StackFit.expand, children: [
        if (_imageBytes != null)
          Image.memory(_imageBytes!, fit: BoxFit.cover),
        Positioned(
          bottom: 12, right: 12,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.60),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.25)),
              ),
              child: const Row(children: [
                Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
                SizedBox(width: 6),
                Text('ถ่ายใหม่',
                    style: TextStyle(color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── GPS info card (checkout records location but no zone restriction) ─────

  Widget _buildGpsInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: _fetchingPos
          ? Row(children: [
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white54, strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('กำลังดึงตำแหน่ง...',
                  style: TextStyle(fontSize: 12,
                      color: Colors.white.withOpacity(0.50))),
            ])
          : Row(children: [
              Icon(
                _checkoutPos != null
                    ? Icons.location_on_rounded
                    : Icons.location_on_outlined,
                color: _checkoutPos != null
                    ? const Color(0xFF1D9E75)
                    : Colors.white.withOpacity(0.45),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _checkoutPos != null
                    ? Text(
                        'ตำแหน่งพร้อม · ${_checkoutPos!.latitude.toStringAsFixed(5)}, '
                        '${_checkoutPos!.longitude.toStringAsFixed(5)}',
                        style: TextStyle(fontSize: 12,
                            color: Colors.white.withOpacity(0.60)),
                      )
                    : Text('ระบบจะบันทึกพิกัดอัตโนมัติเมื่อเช็คเอาท์',
                        style: TextStyle(fontSize: 12,
                            color: Colors.white.withOpacity(0.40))),
              ),
              if (_checkoutPos == null && !_fetchingPos)
                GestureDetector(
                  onTap: _prefetchLocation,
                  child: Text('รีเฟรช',
                      style: TextStyle(fontSize: 11, color: _accent,
                          fontWeight: FontWeight.w600)),
                ),
            ]),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    final ready = _imageFile != null && !_isSubmitting;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        icon: _isSubmitting
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : const Icon(Icons.check_circle_rounded, size: 22),
        label: Text(
          _isSubmitting ? 'กำลังบันทึก...' : 'ยืนยัน Check Out',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              letterSpacing: 0.4),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ready ? _accent : Colors.white.withOpacity(0.15),
          foregroundColor: ready ? Colors.black87 : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _isSubmitting ? null : _submitCheckOut,
      ),
    );
  }
}
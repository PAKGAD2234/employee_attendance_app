import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // ← kIsWeb อยู่ที่นี่

// ─────────────────────────────────────────────────────────────────────────────
// CheckInUI
// ─────────────────────────────────────────────────────────────────────────────
class CheckInUI extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String employeePhone;

  const CheckInUI({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.employeePhone,
  });

  @override
  State<CheckInUI> createState() => _CheckInUIState();
}

class _CheckInUIState extends State<CheckInUI>
    with SingleTickerProviderStateMixin {
  // ── Services ────────────────────────────────────────────────────────────────
  final _supabase = Supabase.instance.client;

  // ── UI state ─────────────────────────────────────────────────────────────
  XFile? _imageFile;
  Uint8List? _imageBytes;
  bool _isSubmitting = false;

  // ── Live clock ───────────────────────────────────────────────────────────
  late DateTime _now;
  Timer? _clockTimer;

  // ── Fade animation ────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── GPS / zone state ───────────────────────────────────────────────────────
  /// null = still checking, true = inside zone, false = outside zone
  bool? _inZone;
  String _locationMsg = 'กำลังตรวจสอบตำแหน่ง...';
  double? _distanceMeters;
  String _siteName = '';
  double? _siteLat;
  double? _siteLng;
  double _siteRadius = 100;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();

    // Live clock — tick every second
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Fade-in animation
    _fadeCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
          ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    // Load site config then check GPS
    _initLocationCheck();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GPS Permission Helper
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the current position after handling all permission edge-cases.
  /// Throws a descriptive [Exception] if unable to get location.
   Future<Position> _ensureLocationAndGet() async {
  if (kIsWeb) {
    // Web — ใช้ Geolocator โดยตรง browser จัดการ permission เอง
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  // Mobile — ใช้ permission_handler ตามปกติ
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('location_service_disabled');
  }
  final status = await Permission.locationWhenInUse.request();
  if (status.isPermanentlyDenied) {
    throw Exception('location_permanently_denied');
  }
  if (status.isDenied) {
    throw Exception('location_denied');
  }
  return Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
    timeLimit: const Duration(seconds: 15),
  );
}

  // ─────────────────────────────────────────────────────────────────────────
  // Load site config + run zone check
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initLocationCheck() async {
    setState(() {
      _inZone = null;
      _locationMsg = 'กำลังตรวจสอบตำแหน่ง...';
    });

    try {
      // ── Step 1: fetch employee's assigned work-site ─────────────────────
      final emp = await _supabase
          .from('employees')
          .select('work_sites(name, gps_lat, gps_lng, gps_radius)')
          .eq('id', widget.employeeId)
          .single();

      final site = emp['work_sites'] as Map?;
      if (site != null) {
        _siteName = site['name'] ?? '';
        _siteLat = (site['gps_lat'] as num?)?.toDouble();
        _siteLng = (site['gps_lng'] as num?)?.toDouble();
        _siteRadius = (site['gps_radius'] as num?)?.toDouble() ?? 100;
      }

      // ── Step 2: if no GPS configured → allow freely ────────────────────
      if (_siteLat == null || _siteLng == null) {
        if (mounted) {
          setState(() {
            _inZone = true;
            _locationMsg = _siteName.isNotEmpty
                ? '$_siteName (ไม่มี GPS zone)'
                : 'ไม่มีการตั้งค่า GPS zone';
          });
        }
        return;
      }

      // ── Step 3: get device location ────────────────────────────────────
      final pos = await _ensureLocationAndGet();

      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        _siteLat!, _siteLng!,
      );

      final distLabel = dist >= 1000
          ? '${(dist / 1000).toStringAsFixed(2)} กม.'
          : '${dist.toStringAsFixed(0)} ม.';

      if (mounted) {
        setState(() {
          _distanceMeters = dist;
          _inZone = dist <= _siteRadius;
          _locationMsg = _inZone!
              ? 'คุณอยู่ในพื้นที่ทำงาน ✓  (ห่าง $distLabel)'
              : 'อยู่นอกพื้นที่ทำงาน\nระยะห่าง $distLabel จากสาขา\n(รัศมีอนุญาต ${_siteRadius.toStringAsFixed(0)} ม.)';
        });
      }
    } on Exception catch (e) {
      _handleLocationError(e.toString());
    } catch (e) {
      _handleLocationError(e.toString());
    }
  }

  void _handleLocationError(String raw) {
    String msg;
    if (raw.contains('location_service_disabled')) {
      msg = 'กรุณาเปิด GPS ในการตั้งค่าโทรศัพท์';
    } else if (raw.contains('location_permanently_denied')) {
      msg = 'ถูกปฏิเสธ GPS ถาวร\nไปที่ การตั้งค่า → แอป → อนุญาตตำแหน่ง';
    } else if (raw.contains('location_denied')) {
      msg = 'ต้องการสิทธิ์ GPS เพื่อเช็คอิน';
    } else {
      msg = 'ไม่สามารถตรวจสอบตำแหน่งได้\n$raw';
    }
    if (mounted) {
      setState(() {
        _inZone = false;
        _locationMsg = msg;
      });
    }
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
  // Check-in submission
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _submitCheckIn() async {
    // Guard conditions
    if (_imageFile == null) {
      _snack('กรุณาถ่ายรูปก่อน', isError: true);
      return;
    }
    if (_inZone != true) {
      _snack('คุณอยู่นอกพื้นที่ทำงาน ไม่สามารถเช็คอินได้', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final pos = await _ensureLocationAndGet();
      final now = DateTime.now().toLocal();
      final today = _dateStr(now);

      // ── Duplicate check ────────────────────────────────────────────────
      final existing = await _supabase
          .from('attendance')
          .select('id')
          .eq('employee_id', widget.employeeId)
          .eq('work_date', today)
          .limit(1);
      if (existing.isNotEmpty) {
        _snack('เช็คอินวันนี้ไปแล้ว', isError: true);
        return;
      }

      // ── Employee schedule ──────────────────────────────────────────────
      final empData = await _supabase
          .from('employees')
          .select('work_start_time, late_threshold_minutes, work_site_id')
          .eq('id', widget.employeeId)
          .single();

      final parts = (empData['work_start_time'] as String).split(':');
      final workStart = DateTime(
          now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
      final threshold = (empData['late_threshold_minutes'] as int?) ?? 15;
      final isLate = now.isAfter(workStart.add(Duration(minutes: threshold)));

      // ── Upload photo ───────────────────────────────────────────────────
      final fileName = '${now.millisecondsSinceEpoch}.jpg';
      final bytes = await _imageFile!.readAsBytes();
      await _supabase.storage.from('attendance').uploadBinary(fileName, bytes);

      // ── Insert attendance record ───────────────────────────────────────
      await _supabase.from('attendance').insert({
        'employee_id': widget.employeeId,
        'work_date': today,
        'checkin_time': now.toIso8601String(),
        'checkin_lat': pos.latitude,
        'checkin_lng': pos.longitude,
        'checkin_photo': fileName,
        'status': 'checkin',
        'late': isLate,
        'work_site_id': empData['work_site_id'],
      });

      // ── Notification ───────────────────────────────────────────────────
      await _supabase.from('notifications').insert({
        'type': isLate ? 'late' : 'checkin',
        'employee_name': widget.employeeName,
        'employee_phone': widget.employeePhone,
        'message': isLate
            ? '⚠️ ${widget.employeeName} เช็คอินสาย'
            : '✅ ${widget.employeeName} เช็คอินแล้ว',
        'work_site_id': empData['work_site_id'],
        'is_read': false,
      });

      // Optional push notification edge function
      try {
        await _supabase.functions.invoke('push-notify', body: {
          'title': isLate ? '⚠️ มาสาย' : '✅ เช็คอินแล้ว',
          'body': '${widget.employeeName} • ${_timeStr(now)}',
        });
      } catch (_) {} // non-critical

      _snack(isLate ? 'เช็คอินสำเร็จ (สาย) ⚠️' : 'เช็คอินสำเร็จ ✓');
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
      backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF0277BD),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  static const _blue = Color(0xFF29B6F6);
  static const _green = Color(0xFF1D9E75);

  Color get _zoneColor {
    if (_inZone == null) return Colors.white54;
    return _inZone! ? _green : Colors.red.shade300;
  }

  Color get _zoneBg {
    if (_inZone == null) return Colors.white.withOpacity(0.06);
    return _inZone!
        ? _green.withOpacity(0.15)
        : Colors.red.shade800.withOpacity(0.25);
  }

  Color get _zoneBorder {
    if (_inZone == null) return Colors.white.withOpacity(0.12);
    return _inZone!
        ? _green.withOpacity(0.50)
        : Colors.red.withOpacity(0.50);
  }

  bool get _canSubmit =>
      !_isSubmitting && _inZone == true && _imageFile != null;

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background ─────────────────────────────────────────────────
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

          // ── Decorative ring ────────────────────────────────────────────
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _blue.withOpacity(0.12), width: 1.5),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
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
                          _buildLocationCard(),
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

  // ── AppBar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Text('Check In',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const Spacer(),
          _badgeChip(Icons.login_rounded, 'เข้างาน', _blue),
        ],
      ),
    );
  }

  Widget _badgeChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 12, color: color,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Clock card ───────────────────────────────────────────────────────────

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
        Text(
          _timeStr(_now),
          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: 3),
        ),
        const SizedBox(height: 4),
        Text(_thaiDate(_now),
            style: TextStyle(fontSize: 13,
                color: Colors.white.withOpacity(0.50))),
      ]),
    );
  }

  // ── Photo area ───────────────────────────────────────────────────────────

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
                ? _blue.withOpacity(0.55)
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
          color: _blue.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: _blue.withOpacity(0.35), width: 1.5),
        ),
        child: const Icon(Icons.camera_alt_rounded, color: _blue, size: 32),
      ),
      const SizedBox(height: 14),
      const Text('แตะเพื่อถ่ายรูป',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: _blue)),
      const SizedBox(height: 4),
      Text('จำเป็นต้องถ่ายรูปก่อนเช็คอิน',
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

  // ── Location card ────────────────────────────────────────────────────────

  Widget _buildLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _zoneBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _zoneBorder),
      ),
      child: _inZone == null ? _locationLoading() : _locationResult(),
    );
  }

  Widget _locationLoading() {
    return Row(children: [
      const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(
              color: Colors.white54, strokeWidth: 2)),
      const SizedBox(width: 12),
      Text('กำลังตรวจสอบตำแหน่ง...',
          style: TextStyle(fontSize: 13,
              color: Colors.white.withOpacity(0.55))),
    ]);
  }

  Widget _locationResult() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Site name + status icon row ─────────────────────────────────
      Row(children: [
        Icon(
          _inZone! ? Icons.location_on_rounded : Icons.location_off_rounded,
          color: _zoneColor, size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _siteName.isNotEmpty ? _siteName : 'สถานที่ทำงาน',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: _zoneColor),
          ),
        ),
        // ── Status badge ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _inZone!
                ? _green.withOpacity(0.25)
                : Colors.red.withOpacity(0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _inZone!
                    ? _green.withOpacity(0.5)
                    : Colors.red.withOpacity(0.5)),
          ),
          child: Text(
            _inZone! ? 'อยู่ในพื้นที่' : 'นอกพื้นที่',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: _zoneColor),
          ),
        ),
      ]),

      const SizedBox(height: 10),

      // ── Distance info bar ──────────────────────────────────────────
      if (_distanceMeters != null)
        _distanceBar(),

      const SizedBox(height: 8),

      // ── Message ────────────────────────────────────────────────────
      Text(_locationMsg,
          style: TextStyle(fontSize: 12,
              color: _inZone!
                  ? Colors.white.withOpacity(0.75)
                  : Colors.red.shade200,
              height: 1.5)),

      // ── Retry button ───────────────────────────────────────────────
      if (_inZone == false) ...[
        const SizedBox(height: 12),
        _retryButton(),
      ],
    ]);
  }

  Widget _distanceBar() {
    final dist = _distanceMeters!;
    final ratio = (_siteRadius > 0 ? dist / _siteRadius : 1.0).clamp(0.0, 1.0);
    final label = dist >= 1000
        ? '${(dist / 1000).toStringAsFixed(2)} กม.'
        : '${dist.toStringAsFixed(0)} ม.';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.straighten_rounded, size: 13, color: Colors.white54),
        const SizedBox(width: 6),
        Text('ระยะห่างปัจจุบัน: $label',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const Spacer(),
        Text('รัศมี: ${_siteRadius.toStringAsFixed(0)} ม.',
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio,
          backgroundColor: Colors.white.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation<Color>(
              _inZone! ? _green : Colors.red.shade400),
          minHeight: 6,
        ),
      ),
    ]);
  }

  Widget _retryButton() {
    return GestureDetector(
      onTap: _initLocationCheck,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.refresh_rounded, color: Colors.white70, size: 15),
          SizedBox(width: 6),
          Text('ตรวจสอบตำแหน่งอีกครั้ง',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
    );
  }

  // ── Submit button ────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    String label;
    IconData icon;
    Color bgColor;

    if (_isSubmitting) {
      label = 'กำลังบันทึก...';
      icon = Icons.hourglass_top_rounded;
      bgColor = _blue;
    } else if (_inZone == null) {
      label = 'กำลังตรวจสอบตำแหน่ง...';
      icon = Icons.gps_not_fixed_rounded;
      bgColor = Colors.white.withOpacity(0.15);
    } else if (_inZone == false) {
      label = 'ไม่อยู่ในพื้นที่ทำงาน';
      icon = Icons.location_off_rounded;
      bgColor = Colors.white.withOpacity(0.15);
    } else if (_imageFile == null) {
      label = 'กรุณาถ่ายรูปก่อน';
      icon = Icons.camera_alt_outlined;
      bgColor = Colors.white.withOpacity(0.15);
    } else {
      label = 'ยืนยัน Check In';
      icon = Icons.check_circle_rounded;
      bgColor = _blue;
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        icon: _isSubmitting
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Icon(icon, size: 22),
        label: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _canSubmit ? _submitCheckIn : null,
      ),
    );
  }
}
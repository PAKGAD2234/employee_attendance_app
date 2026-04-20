import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class EmployeeHistoryUI extends StatefulWidget {
  final String employeeId;
  const EmployeeHistoryUI({super.key, required this.employeeId});

  @override
  State<EmployeeHistoryUI> createState() => _EmployeeHistoryUIState();
}

class _EmployeeHistoryUIState extends State<EmployeeHistoryUI>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  List attendance = [];
  bool isLoading = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    supabaseService.initialize(supabase);
    loadData();

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

  Future<void> loadData() async {
    try {
      final data =
          await supabaseService.getEmployeeAttendance(widget.employeeId);
      setState(() {
        attendance = data;
        isLoading = false;
      });
      _fadeController.forward(from: 0);
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  String _getImageUrl(String? photoValue) {
    if (photoValue == null || photoValue.isEmpty) return '';
    if (photoValue.startsWith('http')) return photoValue;
    return supabase.storage.from('attendance').getPublicUrl(photoValue);
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return '-';
    }
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      const thDays = ['จันทร์','อังคาร','พุธ','พฤหัส','ศุกร์','เสาร์','อาทิตย์'];
      const thMonths = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                        'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
      return 'วัน${thDays[dt.weekday - 1]}ที่ ${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}';
    } catch (_) {
      return '-';
    }
  }

  // คำนวณชั่วโมงทำงาน
  String _calcDuration(dynamic checkInRaw, dynamic checkOutRaw) {
    try {
      if (checkInRaw == null || checkOutRaw == null) return '-';
      final inTime = DateTime.parse(checkInRaw.toString()).toLocal();
      final outTime = DateTime.parse(checkOutRaw.toString()).toLocal();
      final diff = outTime.difference(inTime);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return '${h}ชม. ${m}น.';
    } catch (_) {
      return '-';
    }
  }

  void _showPhotoDialog(String url, String label) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF29B6F6).withOpacity(0.20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF29B6F6).withOpacity(0.50)),
                ),
                child: const Text('ปิด',
                    style: TextStyle(color: Color(0xFF29B6F6))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoThumb(String? rawUrl, String label) {
    final url = _getImageUrl(rawUrl);
    if (url.isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        ),
        child: Icon(Icons.image_not_supported_outlined,
            color: Colors.white.withOpacity(0.25), size: 22),
      );
    }
    return GestureDetector(
      onTap: () => _showPhotoDialog(url, label),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF29B6F6).withOpacity(0.45), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF29B6F6).withOpacity(0.20),
              blurRadius: 8,
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined,
                  color: Colors.white.withOpacity(0.30))),
        ),
      ),
    );
  }

  Widget _timeChip({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.45),
                    letterSpacing: 0.3)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: time == '-' ? Colors.white.withOpacity(0.25) : color,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Map record, int index) {
    final checkIn = record['checkin_time'] != null
        ? _formatTime(record['checkin_time'])
        : '-';
    final checkOut = record['checkout_time'] != null
        ? _formatTime(record['checkout_time'])
        : '-';
    final date = _formatDate(record['work_date'].toString());
    final duration =
        _calcDuration(record['checkin_time'], record['checkout_time']);
    final hasCheckOut = record['checkout_time'] != null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => Opacity(
        opacity: val,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - val)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(22),
          border:
              Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Date row ──────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF29B6F6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF29B6F6).withOpacity(0.35),
                        width: 1),
                  ),
                  child: Text(date,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF29B6F6),
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                if (duration != '-')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 13,
                            color: Colors.white.withOpacity(0.45)),
                        const SizedBox(width: 4),
                        Text(duration,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.55))),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Time row ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _timeChip(
                    icon: Icons.login_rounded,
                    label: 'เข้างาน',
                    time: checkIn,
                    color: const Color(0xFF29B6F6),
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.10),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                Expanded(
                  child: _timeChip(
                    icon: Icons.logout_rounded,
                    label: 'ออกงาน',
                    time: checkOut,
                    color: hasCheckOut
                        ? const Color(0xFF26C6DA)
                        : Colors.white.withOpacity(0.25),
                  ),
                ),
              ],
            ),

            // ── Photos ────────────────────────────────────────
            if (record['checkin_photo'] != null ||
                record['checkout_photo'] != null) ...[
              const SizedBox(height: 14),
              Divider(color: Colors.white.withOpacity(0.08), height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('รูปภาพ',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.40),
                          letterSpacing: 0.3)),
                  const SizedBox(width: 12),
                  _photoThumb(record['checkin_photo'], 'ภาพเข้างาน'),
                  const SizedBox(width: 10),
                  _photoThumb(record['checkout_photo'], 'ภาพออกงาน'),
                ],
              ),
            ],
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
          // ── Background ────────────────────────────────────────
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

          // ── Decor circle ──────────────────────────────────────
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
                    width: 1.5),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── AppBar ──────────────────────────────────────
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
                        'ประวัติการลงเวลา',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      // จำนวนรายการ
                      if (!isLoading && attendance.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF29B6F6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    const Color(0xFF29B6F6).withOpacity(0.35)),
                          ),
                          child: Text(
                            '${attendance.length} รายการ',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF29B6F6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Body ────────────────────────────────────────
                Expanded(
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                          color: Color(0xFF29B6F6),
                          strokeWidth: 2.5,
                        ))
                      : attendance.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history_toggle_off_rounded,
                                      size: 64,
                                      color: Colors.white.withOpacity(0.20)),
                                  const SizedBox(height: 16),
                                  Text('ยังไม่มีข้อมูลการลงเวลา',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color:
                                              Colors.white.withOpacity(0.40))),
                                ],
                              ),
                            )
                          : FadeTransition(
                              opacity: _fadeAnim,
                              child: RefreshIndicator(
                                onRefresh: loadData,
                                color: const Color(0xFF29B6F6),
                                backgroundColor:
                                    const Color(0xFF0D1B2A),
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(
                                      top: 4, bottom: 32),
                                  itemCount: attendance.length,
                                  itemBuilder: (_, i) =>
                                      _buildCard(attendance[i], i),
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
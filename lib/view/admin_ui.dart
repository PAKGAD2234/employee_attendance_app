import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'add_employee_ui.dart';

class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  List employees = [];
  List attendance = [];
  bool isLoading = true;
  int _currentNavIndex = 0;

  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  // สีหลัก
  static const Color blue800 = Color(0xFF0C447C);
  static const Color blue600 = Color(0xFF185FA5);
  static const Color blue400 = Color(0xFF378ADD);
  static const Color blue100 = Color(0xFFB5D4F4);
  static const Color blue50  = Color(0xFFE6F1FB);
  static const Color teal400 = Color(0xFF1D9E75);
  static const Color teal50  = Color(0xFFE1F5EE);
  static const Color red400  = Color(0xFFE24B4A);
  static const Color red50   = Color(0xFFFCEBEB);
  static const Color amber400 = Color(0xFFBA7517);
  static const Color amber50  = Color(0xFFFAEEDA);
  static const Color gray400  = Color(0xFF888780);
  static const Color gray50   = Color(0xFFF1EFE8);
  static const Color bgColor  = Color(0xFFF0F5FB);

  @override
  void initState() {
    super.initState();
    supabaseService.initialize(supabase);
    loadData();
  }

  Future<void> loadData() async {
    try {
      final empData = await supabaseService.getEmployees();
      final attData = await supabaseService.getAttendanceWithImages();
      setState(() {
        employees = empData;
        attendance = attData;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> deleteEmployee(String id, String name) async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("ยืนยันการลบ"),
        content: Text("ต้องการลบ $name ใช่หรือไม่?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await supabaseService.deleteEmployee(id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("ลบพนักงานสำเร็จ")));
                  loadData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("ลบ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── HELPER ─────────────────────────────────────────────
  String _formatTime(String? iso) {
    if (iso == null) return '--:--';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _getImageUrl(String? val) {
    if (val == null || val.isEmpty) return '';
    if (val.startsWith('http')) return val;
    return supabase.storage.from('attendance').getPublicUrl(val);
  }

  // กรองข้อมูล attendance ตามวันที่เลือก
  List get _filteredAttendance {
    return attendance.where((r) {
      final workDate = r['work_date']?.toString() ?? '';
      if (workDate.isEmpty) return false;
      try {
        final dt = DateTime.parse(workDate);
        return dt.year == _selectedDate.year &&
            dt.month == _selectedDate.month &&
            dt.day == _selectedDate.day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  // ─── BUILD ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: blue600))
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: IndexedStack(
                    index: _currentNavIndex,
                    children: [
                      _buildHomeTab(),
                      _buildEmployeesTab(),
                      _buildAttendanceTab(),
                      _buildSettingsTab(),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: (_currentNavIndex == 0 || _currentNavIndex == 1)
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddEmployeeUI()))
                    .then((_) => loadData());
              },
              backgroundColor: blue600,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  // ─── HEADER ──────────────────────────────────────────────
  Widget _buildHeader() {
    final presentCount = attendance
        .where((r) => r['checkin_time'] != null)
        .length;
    final lateCount = attendance.where((r) => r['late'] == true).length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [blue800, blue600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("ยินดีต้อนรับ",
                        style: TextStyle(color: blue100, fontSize: 13)),
                    Text("Admin Dashboard",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.logout,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _headerStat('${employees.length}', 'พนักงาน'),
              const SizedBox(width: 10),
              _headerStat('$presentCount', 'มาแล้ว'),
              const SizedBox(width: 10),
              _headerStat('$lateCount', 'ขาด/สาย'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String num, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Text(num,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: blue100, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ─── BOTTOM NAV ──────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'หน้าหลัก'},
      {'icon': Icons.people_rounded, 'label': 'พนักงาน'},
      {'icon': Icons.calendar_today_rounded, 'label': 'Attendance'},
      {'icon': Icons.settings_rounded, 'label': 'ตั้งค่า'},
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: blue100, width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (i) {
            final active = i == _currentNavIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _currentNavIndex = i),
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? blue50 : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(items[i]['icon'] as IconData,
                            color: active ? blue600 : gray400,
                            size: 22),
                      ),
                      const SizedBox(height: 3),
                      Text(items[i]['label'] as String,
                          style: TextStyle(
                              fontSize: 10,
                              color: active ? blue600 : gray400,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─── TAB: HOME ───────────────────────────────────────────
  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: loadData,
      color: blue600,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCalendarCard(),
          const SizedBox(height: 16),
          _buildDaySummary(),
          const SizedBox(height: 16),
          _buildSectionTitle('รายชื่อวันที่เลือก'),
          const SizedBox(height: 8),
          ..._filteredAttendance.map((r) => _buildAttendanceCard(r)),
          if (_filteredAttendance.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('ไม่มีข้อมูลวันที่เลือก',
                    style: TextStyle(color: gray400)),
              ),
            ),
        ],
      ),
    );
  }

  // ─── CALENDAR ────────────────────────────────────────────
  Widget _buildCalendarCard() {
    final thaiMonths = [
      'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
      'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
      'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
    ];
    final buddhistYear = _focusedMonth.year + 543;
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final today = DateTime.now();

    // หา date ที่มีข้อมูล late จาก attendance
    final lateSet = <int>{};
    final presentSet = <int>{};
    for (final r in attendance) {
      final workDate = r['work_date']?.toString() ?? '';
      if (workDate.isEmpty) continue;
      try {
        final dt = DateTime.parse(workDate);
        if (dt.year == _focusedMonth.year && dt.month == _focusedMonth.month) {
          if (r['late'] == true) {
            lateSet.add(dt.day);
          } else {
            presentSet.add(dt.day);
          }
        }
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue100),
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Text(
                '${thaiMonths[_focusedMonth.month - 1]} $buddhistYear',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: blue800),
              ),
              const Spacer(),
              _calNavBtn(Icons.chevron_left, () {
                setState(() {
                  _focusedMonth = DateTime(
                      _focusedMonth.year, _focusedMonth.month - 1, 1);
                });
              }),
              const SizedBox(width: 6),
              _calNavBtn(Icons.chevron_right, () {
                setState(() {
                  _focusedMonth = DateTime(
                      _focusedMonth.year, _focusedMonth.month + 1, 1);
                });
              }),
            ],
          ),
          const SizedBox(height: 12),
          // Day headers
          Row(
            children: ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'].map((d) {
              return Expanded(
                child: Center(
                  child: Text(d,
                      style: const TextStyle(
                          fontSize: 11, color: gray400, fontWeight: FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (_, idx) {
              if (idx < firstWeekday) return const SizedBox();
              final day = idx - firstWeekday + 1;
              final isToday = today.year == _focusedMonth.year &&
                  today.month == _focusedMonth.month &&
                  today.day == day;
              final isSelected = _selectedDate.year == _focusedMonth.year &&
                  _selectedDate.month == _focusedMonth.month &&
                  _selectedDate.day == day;
              final isLate = lateSet.contains(day);
              final isPresent = presentSet.contains(day);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = DateTime(
                        _focusedMonth.year, _focusedMonth.month, day);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? blue600
                        : isToday
                            ? blue50
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white
                              : isToday
                                  ? blue600
                                  : const Color(0xFF1a2a3a),
                          fontWeight: isSelected || isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (!isSelected && (isLate || isPresent))
                        Positioned(
                          bottom: 3,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isLate ? red400 : teal400,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _legendDot(teal400, 'ปกติ'),
              const SizedBox(width: 12),
              _legendDot(red400, 'มีขาด/สาย'),
              const SizedBox(width: 12),
              _legendDot(blue600, 'เลือก'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calNavBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: blue50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: blue600, size: 18),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: gray400)),
      ],
    );
  }

  // ─── DAY SUMMARY CHIPS ───────────────────────────────────
  Widget _buildDaySummary() {
    final filtered = _filteredAttendance;
    final presentCount = filtered.where((r) => r['checkin_time'] != null && r['late'] != true).length;
    final lateCount = filtered.where((r) => r['late'] == true).length;
    final absentCount = employees.length - filtered.length;

    return Row(
      children: [
        _summaryChip('มาแล้ว', '$presentCount', teal400, teal50, const Color(0xFF9FE1CB)),
        const SizedBox(width: 8),
        _summaryChip('สาย', '$lateCount', amber400, amber50, const Color(0xFFFAC775)),
        const SizedBox(width: 8),
        _summaryChip('ขาด', '$absentCount', red400, red50, const Color(0xFFF7C1C1)),
      ],
    );
  }

  Widget _summaryChip(String label, String num, Color textColor,
      Color bgColor2, Color iconBg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: iconBg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(num,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: gray400)),
          ],
        ),
      ),
    );
  }

  // ─── TAB: EMPLOYEES ──────────────────────────────────────
  Widget _buildEmployeesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: blue100),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, color: gray400, size: 18),
                SizedBox(width: 8),
                Text('ค้นหาพนักงาน...',
                    style: TextStyle(color: gray400, fontSize: 13)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _buildSectionTitle('พนักงานทั้งหมด (${employees.length} คน)'),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadData,
            color: blue600,
            child: employees.isEmpty
                ? const Center(child: Text('ไม่มีข้อมูลพนักงาน'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: employees.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildEmployeeCard(employees[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Map emp) {
    final isActive = emp['status'] == 'active';
    final name = emp['full_name'] ?? '-';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;
    final profileUrl = _getImageUrl(emp['profile_photo']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: profileUrl.isNotEmpty
                ? Image.network(
                    profileUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _empAvatarFallback(initials),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : _empAvatarFallback(initials),
                  )
                : _empAvatarFallback(initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1a2a3a))),
                const SizedBox(height: 2),
                Text(
                  '${emp['username'] ?? '-'} · ${emp['department'] ?? '-'}',
                  style: const TextStyle(fontSize: 11, color: gray400),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? teal400 : gray400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => deleteEmployee(emp['id'], name),
                child: const Icon(Icons.delete_outline,
                    color: red400, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── TAB: ATTENDANCE ─────────────────────────────────────
  Widget _buildAttendanceTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: ['วันนี้', 'สัปดาห์นี้', 'เดือนนี้'].map((label) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: label == 'วันนี้' ? blue600 : blue50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: label == 'วันนี้' ? Colors.white : blue600)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadData,
            color: blue600,
            child: attendance.isEmpty
                ? const Center(child: Text('ไม่มีข้อมูล Attendance'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: attendance.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildAttendanceCard(attendance[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(Map record) {
    final empData = record['employees'] as Map?;
    final isLate = record['late'] == true;
    final checkIn = _formatTime(record['checkin_time']);
    final checkOut = _formatTime(record['checkout_time']);
    final workDate = _formatDate(record['work_date']?.toString());
    final name = empData?['full_name'] ?? 'Unknown';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isLate ? amber50 : blue50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isLate ? amber400 : blue800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF1a2a3a))),
                      Text(workDate,
                          style: const TextStyle(
                              fontSize: 11, color: gray400)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$checkIn › $checkOut',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: blue800)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLate ? amber50 : teal50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLate ? 'สาย' : 'ปกติ',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isLate ? amber400 : teal400),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // รูปภาพ check-in
          if (record['checkin_photo'] != null &&
              record['checkin_photo'].toString().isNotEmpty)
            _buildPhotoRow('Check In', _getImageUrl(record['checkin_photo'])),
          // รูปภาพ check-out
          if (record['checkout_photo'] != null &&
              record['checkout_photo'].toString().isNotEmpty)
            _buildPhotoRow('Check Out', _getImageUrl(record['checkout_photo'])),
          // Location
          if (record['checkin_lat'] != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 13, color: blue400),
                  const SizedBox(width: 4),
                  Text(
                    'Lat ${record['checkin_lat']?.toStringAsFixed(4)} / Lng ${record['checkin_lng']?.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 11, color: gray400),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoRow(String label, String url) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: blue50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: blue600)),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showImageDialog(url, label),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        height: 100,
                        color: gray50,
                        child: const Center(
                            child: CircularProgressIndicator(
                                color: blue400, strokeWidth: 2)),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  color: gray50,
                  child: const Center(
                      child: Icon(Icons.image_not_supported,
                          color: gray400)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB: SETTINGS ───────────────────────────────────────
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [blue800, blue600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('AD',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text('admin@company.com',
                      style: TextStyle(color: blue100, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Menu items
        _settingsGroup([
          _settingsItem(Icons.notifications_rounded, 'การแจ้งเตือน', () {}),
          _settingsItem(Icons.access_time_rounded, 'ตั้งเวลาเข้างาน', () {}),
          _settingsItem(Icons.location_on_rounded, 'กำหนด GPS Zone', () {}),
        ]),
        const SizedBox(height: 12),
        _settingsGroup([
          _settingsItem(
  Icons.logout_rounded,
  'ออกจากระบบ',
  () {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
    );
  },
  color: red400,
),
        ]),
      ],
    );
  }

  Widget _settingsGroup(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(children: items),
    );
  }

  Widget _settingsItem(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? const Color(0xFF1a2a3a);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color != null ? red50 : blue50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: color ?? blue600, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 14, color: c))),
            Icon(Icons.chevron_right, color: gray400, size: 18),
          ],
        ),
      ),
    );
  }

  // ─── HELPER WIDGETS ──────────────────────────────────────
  Widget _empAvatarFallback(String initials) {
    return Container(
      width: 44,
      height: 44,
      color: blue50,
      child: Center(
        child: Text(initials,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: blue800, fontSize: 14)),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: blue800));
  }

  void _showImageDialog(String url, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Icon(Icons.image_not_supported, size: 48),
                      )),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:employee_attendance_app/view/schedule_calendar_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

// ══════════════════════════════════════════════════════════
//  CompanyDashboardView
//  รับ workSite map มาแสดงข้อมูลเฉพาะบริษัทนั้น
// ══════════════════════════════════════════════════════════
class CompanyDashboardView extends StatefulWidget {
  final Map<String, dynamic> workSite; // { id, name, address, ... }

  const CompanyDashboardView({super.key, required this.workSite});

  @override
  State<CompanyDashboardView> createState() => _CompanyDashboardViewState();
}

class _CompanyDashboardViewState extends State<CompanyDashboardView>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _unreadNotifications = 0;

  // tab index: 0=ภาพรวม, 1=รายชื่อพนักงาน, 2=รายงาน
  int _tabIndex = 0;

  // calendar state
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  DateTime _reportMonth  = DateTime.now();

  // ─── Color palette (ม่วง-ฟ้า สไตล์ corporate) ──────────
  static const Color primary    = Color(0xFF4F46E5); // indigo
  static const Color primary600 = Color(0xFF4338CA);
  static const Color primary100 = Color(0xFFE0E7FF);
  static const Color primary50  = Color(0xFFEEF2FF);
  static const Color teal       = Color(0xFF0D9488);
  static const Color teal50     = Color(0xFFF0FDFA);
  static const Color amber      = Color(0xFFD97706);
  static const Color amber50    = Color(0xFFFFFBEB);
  static const Color red        = Color(0xFFDC2626);
  static const Color red50      = Color(0xFFFEF2F2);
  static const Color gray       = Color(0xFF6B7280);
  static const Color bg         = Color(0xFFF8FAFC);

  RealtimeChannel? _notifChannel;

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    supabaseService.initialize(supabase);
    _loadData();
    _fetchNotifications();
    _subscribeNotifications();
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    super.dispose();
  }

  // ════════════════════════════════════════════
  // DATA
  // ════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final siteId = widget.workSite['id'].toString();

      // พนักงานของบริษัทนี้เท่านั้น
      final empRes = await supabase
          .from('employees')
          .select()
          .eq('work_site_id', siteId)
          .eq('status', 'active')
          .neq('role', 'admin')
          .order('full_name', ascending: true);

      // attendance เฉพาะพนักงานในบริษัทนี้ และไม่รวมแอดมิน
      final attRes = await supabase
          .from('attendance')
          .select('*, employees!inner(full_name, work_site_id)')
          .eq('employees.work_site_id', siteId)
          .not('employees.role', 'eq', 'admin')
          .order('work_date', ascending: false);

      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(empRes);
          _attendance = List<Map<String, dynamic>>.from(attRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดข้อมูลไม่สำเร็จ: $e')),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  // COMPUTED
  // ════════════════════════════════════════════

  List<Map<String, dynamic>> get _todayAttendance {
    final now = DateTime.now();
    return _attendance.where((r) {
      final d = r['work_date']?.toString() ?? '';
      if (d.isEmpty) return false;
      try {
        final dt = DateTime.parse(d);
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      } catch (_) { return false; }
    }).toList();
  }

  List<Map<String, dynamic>> get _selectedDayAttendance {
    return _attendance.where((r) {
      final d = r['work_date']?.toString() ?? '';
      if (d.isEmpty) return false;
      try {
        final dt = DateTime.parse(d);
        return dt.year == _selectedDate.year &&
            dt.month == _selectedDate.month &&
            dt.day == _selectedDate.day;
      } catch (_) { return false; }
    }).toList();
  }

  int get _todayPresent => _todayAttendance.length;
  int get _todayLate    => _todayAttendance.where((r) => r['late'] == true).length;
  int get _todayAbsent  => _employees.length - _todayPresent;

  // ════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return '--:--'; }
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) { return iso; }
  }

  String _getImageUrl(String? val) {
    if (val == null || val.isEmpty) return '';
    if (val.startsWith('http')) return val;
    return supabase.storage.from('attendance').getPublicUrl(val);
  }

  /// หาว่าพนักงานคนนี้เช็คอินวันที่เลือกหรือยัง
  Map<String, dynamic>? _getAttForEmployee(String empId, DateTime date) {
    try {
      return _attendance.firstWhere((r) {
        final d = r['work_date']?.toString() ?? '';
        if (d.isEmpty) return false;
        final dt = DateTime.parse(d);
        return r['employee_id']?.toString() == empId &&
            dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day;
      });
    } catch (_) { return null; }
  }

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final siteName = widget.workSite['name'] ?? 'บริษัท';

    return Scaffold(
      backgroundColor: bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primary))
          : Column(
              children: [
                _buildHeader(siteName),
                _buildTabBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    color: primary,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
    );
  }
  Widget _buildTodayLabel() {
  final now = DateTime.now();
  final thaiDays = ['อาทิตย์','จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์'];
  final thaiMonths = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                      'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
  final dateLabel = 'วัน${thaiDays[now.weekday % 7]}ที่ ${now.day} ${thaiMonths[now.month - 1]} ${now.year + 543}';
  return Row(
    children: [
      const Icon(Icons.today_rounded, size: 13, color: Colors.white70),
      const SizedBox(width: 6),
      Text(
        dateLabel,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

  // ─── HEADER ──────────────────────────────────────────────
  Widget _buildHeader(String siteName) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF312E81), primary600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 20, right: 20, bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ปุ่มกลับ
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dashboard',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(siteName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              // Refresh button
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _openNotificationCenter,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_none_rounded,
                          color: Colors.white, size: 20),
                    ),
                    if (_unreadNotifications > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
// วันที่ label
() {
  final now = DateTime.now();
  final thaiDays = ['อาทิตย์','จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์'];
  final thaiMonths = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                      'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
  final dateLabel = 'วัน${thaiDays[now.weekday % 7]}ที่ ${now.day} ${thaiMonths[now.month - 1]} ${now.year + 543}';
  return Row(
    children: [
      const Icon(Icons.today_rounded, size: 13, color: Colors.white70),
      const SizedBox(width: 6),
      Text(dateLabel,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
    ],
  );
}(),
const SizedBox(height: 8),
// Summary chips (วันนี้)
Row(
  children: [
    _headerChip('มาแล้ว', '$_todayPresent', teal, const Color(0xFFCCFBF1)),
    const SizedBox(width: 8),
    _headerChip('สาย', '$_todayLate', amber, const Color(0xFFFEF3C7)),
    const SizedBox(width: 8),
    _headerChip('ขาด', '$_todayAbsent', red, const Color(0xFFFEE2E2)),
    const SizedBox(width: 8),
    _headerChip('พนักงาน', '${_employees.length}', Colors.white, Colors.white24),
  ],
),
        ],
      ),
    );
  }

  void _subscribeNotifications() {
    _notifChannel?.unsubscribe();
    _notifChannel = supabase
        .channel('notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _fetchNotifications(),
        )
        .subscribe();
  }

  Future<void> _fetchNotifications() async {
    try {
      final siteId = widget.workSite['id'].toString();
      final data = await supabase
          .from('notifications')
          .select()
          .eq('work_site_id', siteId)
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
          _unreadNotifications = _notifications.where((n) {
            final v = n['is_read'];
            return v == false || v == null;
          }).length;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final siteId = widget.workSite['id'].toString();
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('work_site_id', siteId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Error marking notifications as read: $e');
    }
  }

  void _openNotificationCenter() {
    setState(() => _unreadNotifications = 0);
    _markAllAsRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: gray.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10)),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('ศูนย์แจ้งเตือน',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
              ),
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Text('ไม่มีการแจ้งเตือนในขณะนี้', style: TextStyle(color: gray)))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final item = _notifications[index];
                          final bool isLate = item['type'] == 'late';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isLate ? red50 : teal50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isLate ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                  color: isLate ? red : teal,
                                  size: 20,
                                ),
                              ),
                              title: Text(item['employee_name'] ?? 'ไม่ระบุชื่อ',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['message'] ?? '', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(_formatTimeAgo(item['created_at']?.toString()),
                                      style: const TextStyle(fontSize: 10, color: gray)),
                                ],
                              ),
                              trailing: isLate && (item['employee_phone']?.toString().isNotEmpty ?? false)
                                  ? IconButton(
                                      icon: const Icon(Icons.phone_enabled_rounded, color: primary, size: 20),
                                      onPressed: () => _makePhoneCall(item['employee_phone']?.toString()),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'ไม่ระบุเวลา';
    try {
      final DateTime dateTime = DateTime.parse(isoString).toLocal();
      final Duration diff = DateTime.now().difference(dateTime);
      if (diff.inMinutes < 1) return 'เมื่อครู่นี้';
      if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
      if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
      if (diff.inDays == 1) return 'เมื่อวานนี้';
      if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
      return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
    } catch (e) {
      return 'รูปแบบเวลาผิดพลาด';
    }
  }

  Future<void> _makePhoneCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

Widget _headerChip(
  String label,
  String value,
  Color valueColor,
  Color bg2,
) =>
    Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bg2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: valueColor.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

  // ─── TAB BAR ─────────────────────────────────────────────
  Widget _buildTabBar() {
    final tabs = ['ภาพรวม', 'พนักงาน', 'รายงาน'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == _tabIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tabIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? primary : primary50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(tabs[i],
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : primary)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── BODY ─────────────────────────────────────────────────
  Widget _buildBody() {
    switch (_tabIndex) {
      case 0: return _buildOverviewTab();
      case 1: return _buildEmployeesTab();
      case 2: return _buildReportTab();
      default: return _buildOverviewTab();
    }
  }

  // ════════════════════════════════════════════
  // TAB 0: ภาพรวม
  // ════════════════════════════════════════════
 Widget _buildOverviewTab() {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // ── ปุ่มดูตารางกะ ──────────────────────────────────
      GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScheduleCalendarUI(
              initialSiteId: widget.workSite['id'].toString(),
              showOverrideButton: false, // ซ่อนปุ่มแก้ไขตารางกะในหน้า dashboard
            ),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF312E81), primary600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ตารางกะทั้งเดือน',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white70, size: 14),
            ],
          ),
        ),
      ),
      // ── ปฏิทิน ─────────────────────────────────────────
      _buildCalendar(),
      const SizedBox(height: 16),
      _buildSelectedDaySection(),
    ],
  );
}

   Widget _buildCalendar() {
  final thaiMonths = [
    'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน',
    'พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม',
    'กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
  ];
  final buddhistYear = _focusedMonth.year + 543;
  final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
  final firstWeekday = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
  final today = DateTime.now();

  // วันที่มีคนมา / สาย ในเดือนนี้
  final Map<int, List<Map<String, dynamic>>> dayAttMap = {};
  for (final r in _attendance) {
    final d = r['work_date']?.toString() ?? '';
    if (d.isEmpty) continue;
    try {
      final dt = DateTime.parse(d);
      if (dt.year == _focusedMonth.year && dt.month == _focusedMonth.month) {
        dayAttMap.putIfAbsent(dt.day, () => []).add(r);
      }
    } catch (_) {}
  }

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: primary100),
    ),
    child: Column(
      children: [
        // Month nav
        Row(
          children: [
            Text(
              '${thaiMonths[_focusedMonth.month - 1]} $buddhistYear',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold,
                  color: Color(0xFF1E1B4B)),
            ),
            const Spacer(),
            _calBtn(Icons.chevron_left, () => setState(() =>
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1))),
            const SizedBox(width: 6),
            _calBtn(Icons.chevron_right, () => setState(() =>
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1))),
          ],
        ),
        const SizedBox(height: 12),
        // Weekday headers
        Row(
          children: ['อา','จ','อ','พ','พฤ','ศ','ส'].map((d) => Expanded(
              child: Center(
                child: Text(d, style: const TextStyle(fontSize: 11, color: gray)),
              ))).toList(),
        ),
        const SizedBox(height: 6),
        // Days grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.55,
          ),
          itemCount: firstWeekday + daysInMonth,
          itemBuilder: (_, idx) {
            if (idx < firstWeekday) return const SizedBox();
            final day = idx - firstWeekday + 1;
            final isToday = today.year == _focusedMonth.year &&
                today.month == _focusedMonth.month && today.day == day;
            final isSelected = _selectedDate.year == _focusedMonth.year &&
                _selectedDate.month == _focusedMonth.month &&
                _selectedDate.day == day;

            final dayRecords = dayAttMap[day] ?? [];
            final hasLate = dayRecords.any((r) => r['late'] == true);

            return GestureDetector(
              onTap: () => setState(() =>
                  _selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, day)),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? primary50 : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? primary : isToday ? primary : primary100,
                    width: isSelected || isToday ? 1.5 : 0.5,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // เลขวันที่ + วงกลม
                    Center(
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary
                              : isToday
                                  ? primary
                                  : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected || isToday
                                ? Colors.white
                                : const Color(0xFF1E1B4B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // รายชื่อพนักงานที่มา
                    ...dayRecords.take(2).map((r) {
                      final empData = r['employees'] as Map?;
                      final name = (empData?['full_name'] ?? '-').toString();
                      final firstName = name.split(' ').first;
                      final isLate = r['late'] == true;

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(
                          color: isLate
                              ? amber.withOpacity(0.15)
                              : teal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          firstName,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isLate ? amber : teal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    if (dayRecords.length > 2)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text(
                          '+${dayRecords.length - 2}',
                          style: TextStyle(
                            fontSize: 8,
                            color: primary.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _dot(teal, 'ปกติ'),
            const SizedBox(width: 12),
            _dot(amber, 'สาย'),
            const SizedBox(width: 12),
            _dot(primary, 'เลือก'),
          ],
        ),
      ],
    ),
  );
}

  Widget _calBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: primary50, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: primary, size: 18),
        ),
      );

  Widget _dot(Color color, String label) => Row(
        children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: gray)),
        ],
      );

  Widget _buildSelectedDaySection() {
    final list = _selectedDayAttendance;
    final dateStr = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 16, color: primary),
            const SizedBox(width: 8),
            Text('วันที่ $dateStr',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1B4B))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: primary50, borderRadius: BorderRadius.circular(8)),
              child: Text('${list.length} คน',
                  style: const TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary100)),
            child: const Center(
              child: Text('ไม่มีข้อมูลวันที่เลือก',
                  style: TextStyle(color: gray)),
            ),
          )
        else
          ...list.map((r) => _buildAttCard(r)),
      ],
    );
  }

  // ════════════════════════════════════════════
  // TAB 1: รายชื่อพนักงาน
  // ════════════════════════════════════════════
  Widget _buildEmployeesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Summary row
       
        const SizedBox(height: 16),
        const Row(
          children: [
            Icon(Icons.people_rounded, size: 16, color: primary),
            SizedBox(width: 8),
            Text('รายชื่อพนักงาน',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1B4B))),
          ],
        ),
        const SizedBox(height: 10),
        if (_employees.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary100)),
            child: const Center(child: Text('ยังไม่มีพนักงานในสาขานี้',
                style: TextStyle(color: gray))),
          )
        else
          ..._employees.map((emp) => _buildEmployeeCard(emp)),
      ],
    );
  }

  Widget _empStat(String value, String label, Color color, Color bgColor) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
              color: bgColor, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10, color: gray),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    final name       = emp['full_name'] ?? '-';
    final initials   = name.length >= 2 ? name.substring(0, 2) : name;
    final dept       = emp['department'] ?? '-';
    final phone      = emp['phone'] ?? '';
    final profileUrl = _getImageUrl(emp['profile_photo']);

    // เช็คว่ามาวันนี้ไหม
    final todayAtt   = _getAttForEmployee(emp['id'].toString(), DateTime.now());
    final hasCkIn    = todayAtt != null;
    final isLate     = todayAtt?['late'] == true;

    final checkIn    = hasCkIn ? _fmtTime(todayAtt!['checkin_time']) : '-';
    final checkOut   = hasCkIn ? _fmtTime(todayAtt!['checkout_time']) : '-';
    final checkinPhoto = hasCkIn ? todayAtt!['checkin_photo'] : null;
    final checkoutPhoto = hasCkIn ? todayAtt['checkout_photo'] : null;

    // จำนวนวันทำงานทั้งหมด
    final totalDays  = _attendance
        .where((r) => r['employee_id']?.toString() == emp['id'].toString())
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary100),
      ),
      child: Row(
        children: [
          // Avatar
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: profileUrl.isNotEmpty
                ? Image.network(profileUrl, width: 48, height: 48, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(initials))
                : _avatarFallback(initials),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: Color(0xFF1a1a2e))),
                const SizedBox(height: 2),
                Text(dept, style: const TextStyle(fontSize: 11, color: gray)),
                const SizedBox(height: 4),
                // status วันนี้
                Row(
                  children: [
                    _miniTag(
                      hasCkIn ? (isLate ? 'สาย' : 'มาแล้ว') : 'ยังไม่มา',
                      hasCkIn ? (isLate ? amber : teal) : gray,
                      hasCkIn ? (isLate ? amber50 : teal50) : const Color(0xFFF3F4F6),
                    ),
                    if (hasCkIn) ...[
                      const SizedBox(width: 6),
                      Text('$checkIn › $checkOut',
                          style: const TextStyle(fontSize: 10, color: gray)),
                    ],
                  ],
                ),
                    if (hasCkIn)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            _photoThumb(checkinPhoto, 'ภาพเช็คอิน'),
                            const SizedBox(width: 8),
                            _photoThumb(checkoutPhoto, 'ภาพเช็คเอาท์'),
                          ],
                        ),
                      ),
              ],
            ),
          ),
          // Days stat
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded, size: 16, color: primary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.workSite['name']?.toString() ?? '-',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String initials) => Container(
        width: 48, height: 48, color: primary50,
        child: Center(child: Text(initials,
            style: const TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 16))));

  void _showPhotoDialog(String url, String label) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('ปิด', style: TextStyle(color: Color(0xFF29B6F6))))
          ],
        ),
      ),
    );
  }

  Widget _photoThumb(dynamic rawVal, String label) {
    final url = _getImageUrl(rawVal?.toString());
    if (url.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(Icons.image_not_supported_outlined, size: 18, color: Colors.white.withOpacity(0.25)),
      );
    }
    return GestureDetector(
      onTap: () => _showPhotoDialog(url, label),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, width: 40, height: 40, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 40, height: 40, color: Colors.white.withOpacity(0.06),
              child: Icon(Icons.broken_image_outlined, size: 18, color: Colors.white.withOpacity(0.25)),
            )),
      ),
    );
  }

  Widget _miniTag(String text, Color color, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)));

  // ════════════════════════════════════════════
  // TAB 2: รายงาน (เดือนนี้)
  // ════════════════════════════════════════════
    Widget _buildReportTab() {
  final thaiMonths = [
    'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน',
    'พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม',
    'กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
  ];

  // attendance เดือนที่เลือก
  final monthAtt = _attendance.where((r) {
    final d = r['work_date']?.toString() ?? '';
    if (d.isEmpty) return false;
    try {
      final dt = DateTime.parse(d);
      return dt.year == _reportMonth.year && dt.month == _reportMonth.month;
    } catch (_) { return false; }
  }).toList();

  final monthPresent = monthAtt.length;
  final monthLate    = monthAtt.where((r) => r['late'] == true).length;
  final monthNormal  = monthPresent - monthLate;

  // สรุปรายพนักงานเดือนที่เลือก
  final Map<String, _EmpMonthStat> empStats = {};
  for (final emp in _employees) {
    final id   = emp['id'].toString();
    final name = emp['full_name'] ?? '-';
    empStats[id] = _EmpMonthStat(name: name);
  }
  for (final r in monthAtt) {
    final id = r['employee_id']?.toString() ?? '';
    if (empStats.containsKey(id)) {
      empStats[id]!.total++;
      if (r['late'] == true) empStats[id]!.late++;
    }
  }
  final sortedStats = empStats.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  final buddhistYear = _reportMonth.year + 543;
  final monthLabel   = '${thaiMonths[_reportMonth.month - 1]} $buddhistYear';

  return ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
    children: [
      // ─── Month Picker ──────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary100),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_rounded, size: 18, color: primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'รายงานประจำเดือน $monthLabel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E1B4B),
                ),
              ),
            ),
            // ปุ่ม ย้อนเดือน
            _calBtn(Icons.chevron_left, () {
              setState(() => _reportMonth =
                  DateTime(_reportMonth.year, _reportMonth.month - 1, 1));
            }),
            const SizedBox(width: 6),
            // ปุ่ม ไปเดือนถัดไป (กันเกินเดือนปัจจุบัน)
            _calBtn(
              Icons.chevron_right,
              _reportMonth.year == DateTime.now().year &&
                      _reportMonth.month == DateTime.now().month
                  ? () {} // ไม่ให้กดถ้าเป็นเดือนปัจจุบันแล้ว
                  : () {
                      setState(() => _reportMonth =
                          DateTime(_reportMonth.year, _reportMonth.month + 1, 1));
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // ─── Summary cards ─────────────────────────────────────
      Row(
        children: [
          _reportCard('เช็คอินทั้งหมด', '$monthPresent', 'ครั้ง', primary, primary50,
              Icons.login_rounded),
          const SizedBox(width: 8),
          _reportCard('มาตรงเวลา', '$monthNormal', 'ครั้ง', teal, teal50,
              Icons.check_circle_rounded),
          const SizedBox(width: 8),
          _reportCard('มาสาย', '$monthLate', 'ครั้ง', amber, amber50,
              Icons.warning_rounded),
        ],
      ),
      const SizedBox(height: 20),

      // ─── Per-employee table ────────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: const [
                  Icon(Icons.bar_chart_rounded, size: 16, color: primary),
                  SizedBox(width: 8),
                  Text('สรุปรายพนักงาน',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                          color: Color(0xFF1E1B4B))),
                ],
              ),
            ),
            Container(
              color: primary50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text('ชื่อ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary))),
                  Expanded(child: Center(child: Text('มาทำงาน',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary)))),
                  Expanded(child: Center(child: Text('ตรงเวลา',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: teal)))),
                  Expanded(child: Center(child: Text('สาย',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: amber)))),
                ],
              ),
            ),
            if (sortedStats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('ยังไม่มีข้อมูลเดือนนี้', style: TextStyle(color: gray))),
              )
            else
              ...sortedStats.asMap().entries.map((entry) {
                final i    = entry.key;
                final stat = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: i.isEven ? Colors.white : const Color(0xFFF8FAFF),
                    border: const Border(top: BorderSide(color: Color(0xFFE8EEFF), width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(stat.name,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1a1a2e)),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(child: Center(child: Text('${stat.total}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary)))),
                      Expanded(child: Center(child: Text('${stat.total - stat.late}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: teal)))),
                      Expanded(child: Center(child: Text('${stat.late}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                              color: stat.late > 0 ? amber : gray)))),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
      const SizedBox(height: 20),

      // ─── Recent attendance list ────────────────────────────
      Row(
        children: [
          const Icon(Icons.history_rounded, size: 16, color: primary),
          const SizedBox(width: 8),
          Text('รายการเช็คอิน (${monthAtt.length} รายการ)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                  color: Color(0xFF1E1B4B))),
        ],
      ),
      const SizedBox(height: 10),
      if (monthAtt.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary100)),
          child: const Center(
            child: Text('ไม่มีข้อมูลในเดือนที่เลือก',
                style: TextStyle(color: gray)),
          ),
        )
      else
        ...monthAtt.take(30).map((r) => _buildAttCard(r)),
    ],
  );
}

  Widget _reportCard(String title, String value, String unit,
      Color color, Color bgColor, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
              color: bgColor, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text('$title ($unit)',
                  style: const TextStyle(fontSize: 9, color: gray),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  // ─── Attendance Card (shared) ─────────────────────────────
  Widget _buildAttCard(Map<String, dynamic> r) {
    final empData = r['employees'] as Map?;
    final name    = empData?['full_name'] ?? 'Unknown';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;
    final isLate  = r['late'] == true;
    final checkIn  = _fmtTime(r['checkin_time']);
    final checkOut = _fmtTime(r['checkout_time']);
    final workDate = _fmtDate(r['work_date']?.toString());
    final checkinPhoto = r['checkin_photo']?.toString();
    final checkoutPhoto = r['checkout_photo']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary100),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isLate ? amber50 : primary50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(initials,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                    color: isLate ? amber : primary))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a1a2e))),
                Text(workDate, style: const TextStyle(fontSize: 11, color: gray)),
                if ((checkinPhoto != null && checkinPhoto.isNotEmpty) || (checkoutPhoto != null && checkoutPhoto.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        if (checkinPhoto != null && checkinPhoto.isNotEmpty) ...[
                          _photoThumb(checkinPhoto, 'ภาพเช็คอิน'),
                          const SizedBox(width: 8),
                        ],
                        if (checkoutPhoto != null && checkoutPhoto.isNotEmpty) ...[
                          _photoThumb(checkoutPhoto, 'ภาพเช็คเอาท์'),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$checkIn › $checkOut',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                      color: Color(0xFF1E1B4B))),
              const SizedBox(height: 4),
              _miniTag(
                isLate ? 'สาย' : 'ปกติ',
                isLate ? amber : teal,
                isLate ? amber50 : teal50,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
// Helper model
// ════════════════════════════════════════════
class _EmpMonthStat {
  final String name;
  int total = 0;
  int late  = 0;
  _EmpMonthStat({required this.name});
}
import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:employee_attendance_app/view/schedule_calendar_ui.dart';
import 'package:employee_attendance_app/view/weekly_schedule_ui.dart';
import 'package:employee_attendance_app/view/shift_management_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import 'add_employee_ui.dart';
import '../services/notification_service.dart';

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
  String _searchQuery = '';
  int _unreadCount = 0;
  List _notifications = [];
  List _workSites = [];
  String? _selectedSiteFilter;
  List _leaveData = []; // เพิ่มใน _AdminViewState
  List _weeklySchedules = [];   // ← เพิ่ม
  List _todayOverrides = [];    // ← เพิ่ม 
  bool _shouldWorkToday(String empId) {
  final now = DateTime.now();
  final dayOfWeek = now.weekday % 7;

  final ov = _todayOverrides.cast<Map?>().firstWhere(
    (o) => o!['employee_id'].toString() == empId,
    orElse: () => null,
  );
  if (ov != null) return ov['override_type'] != 'leave';

  return _weeklySchedules.any(
    (w) => w['employee_id'].toString() == empId &&
           w['day_of_week'] == dayOfWeek,
  );
}

  String _timeAgo(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'ไม่ระบุเวลา';
    try {
      final DateTime dateTime = DateTime.parse(isoString).toLocal();
      final Duration diff = DateTime.now().difference(dateTime);
      if (diff.inMinutes < 1)
        return 'เมื่อครู่นี้';
      else if (diff.inMinutes < 60)
        return '${diff.inMinutes} นาทีที่แล้ว';
      else if (diff.inHours < 24)
        return '${diff.inHours} ชั่วโมงที่แล้ว';
      else if (diff.inDays == 1)
        return 'เมื่อวานนี้';
      else if (diff.inDays < 7)
        return '${diff.inDays} วันที่แล้ว';
      else
        return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
    } catch (e) {
      return 'รูปแบบเวลาผิดพลาด';
    }
  }

  int _attendanceFilterIndex = 0;
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  TimeOfDay _defaultWorkStart = const TimeOfDay(hour: 8, minute: 0);
  int _defaultLateThreshold = 15;

  double? _gpsLat;
  double? _gpsLng;
  int _gpsRadius = 100;
  String _companyName = 'บริษัท';

  // ─── Site management state
  final TextEditingController _siteNameController = TextEditingController();
  final TextEditingController _siteLatController = TextEditingController();
  final TextEditingController _siteLngController = TextEditingController();
  final TextEditingController _siteAddressController = TextEditingController();
  int _siteRadius = 100;

  static const Color blue800 = Color(0xFF0C447C);
  static const Color blue600 = Color(0xFF185FA5);
  static const Color blue400 = Color(0xFF378ADD);
  static const Color blue100 = Color(0xFFB5D4F4);
  static const Color blue50 = Color(0xFFE6F1FB);
  static const Color teal400 = Color(0xFF1D9E75);
  static const Color teal50 = Color(0xFFE1F5EE);
  static const Color red400 = Color(0xFFE24B4A);
  static const Color red50 = Color(0xFFFCEBEB);
  static const Color amber400 = Color(0xFFBA7517);
  static const Color amber50 = Color(0xFFFAEEDA);
  static const Color gray400 = Color(0xFF888780);
  static const Color gray50 = Color(0xFFF1EFE8);
  static const Color bgColor = Color(0xFFF0F5FB);

  @override
  void initState() {
    super.initState();
    print('🚀 AdminView initState called');
    NotificationService.init();
    supabaseService.initialize(supabase);
    loadData();
    _loadLeaveData();
    _loadDefaultSchedule();
    _loadGpsZone();
    _fetchNotifications();
    _subscribeNotifications();
    _loadWorkSites();
    _loadScheduleData();
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _siteNameController.dispose();
    _siteLatController.dispose();
    _siteLngController.dispose();
    _siteAddressController.dispose();
    super.dispose();
  }

  RealtimeChannel? _notifChannel;

  void _subscribeNotifications() {
    _notifChannel?.unsubscribe();
    _notifChannel =
        supabase
            .channel('notifications')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              callback: (payload) {
                loadData();
                _fetchNotifications();
              },
            )
            .subscribe();
  }

  Future<void> _loadLeaveData() async {
    try {
      final now = DateTime.now();
      final firstDay = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final lastDay =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${DateTime(now.year, now.month + 1, 0).day}';

      final data = await supabase
          .from('schedule_overrides')
          .select(
            'employee_id, override_date, employees(full_name, profile_photo)',
          )
          .eq('override_type', 'leave')
          .gte('override_date', firstDay)
          .lte('override_date', lastDay);

      if (mounted) setState(() => _leaveData = data);
    } catch (e) {
      debugPrint('Error loading leave data: $e');
    }
  }

// โหลดใน initState
    Future<void> _loadScheduleData() async {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

      final weeklies = await supabase
          .from('employee_weekly_schedules')
          .select('employee_id, day_of_week, shift_template_id')
          .isFilter('effective_until', null);

      final overrides = await supabase
          .from('schedule_overrides')
          .select('employee_id, override_date, override_type')
          .eq('override_date', todayStr);

      if (mounted) setState(() {
        _weeklySchedules = weeklies;
        _todayOverrides = overrides;
      });
    }

  Future<void> _fetchNotifications() async {
    try {
      final data = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) {
        setState(() {
          _notifications = data;
          _unreadCount =
              data.where((n) {
                final v = n['is_read'];
                return v == false || v == null;
              }).length;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  void _openNotificationCenter() {
    setState(() => _unreadCount = 0);
    _markAllAsRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: gray400.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          "ศูนย์แจ้งเตือน",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: blue800,
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                            _notifications.isEmpty
                                ? Center(
                                  child: Text(
                                    "ไม่มีการแจ้งเตือนในขณะนี้",
                                    style: TextStyle(color: gray400),
                                  ),
                                )
                                : ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
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
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.03,
                                            ),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 4,
                                            ),
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isLate ? red50 : teal50,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isLate
                                                ? Icons.warning_amber_rounded
                                                : Icons.check_circle_outline,
                                            color: isLate ? red400 : teal400,
                                            size: 20,
                                          ),
                                        ),
                                        title: Text(
                                          item['employee_name'] ??
                                              'ไม่ระบุชื่อ',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['message'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _timeAgo(item['created_at']),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: gray400,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing:
                                            (isLate &&
                                                    item['employee_phone'] !=
                                                        null)
                                                ? IconButton(
                                                  icon: const Icon(
                                                    Icons.phone_enabled_rounded,
                                                    color: blue600,
                                                    size: 20,
                                                  ),
                                                  onPressed:
                                                      () => _makePhoneCall(
                                                        item['employee_phone'],
                                                      ),
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

  Future<void> _markAllAsRead() async {
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Error marking read: $e');
    }
  }

  // ════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _loadDefaultSchedule() async {
    try {
      final res =
          await supabase
              .from('work_schedules')
              .select()
              .isFilter('employee_id', null)
              .maybeSingle();
      if (res != null && mounted) {
        final parts = (res['work_start_time'] as String).split(':');
        setState(() {
          _defaultWorkStart = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
          _defaultLateThreshold = res['late_threshold_minutes'] ?? 15;
        });
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  // GPS ZONE
  // ════════════════════════════════════════════

  Future<void> _loadGpsZone() async {
    try {
      final res = await supabase.from('gps_zones').select().maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _gpsLat = (res['latitude'] as num?)?.toDouble();
          _gpsLng = (res['longitude'] as num?)?.toDouble();
          _gpsRadius = res['radius_meters'] ?? 100;
          _companyName = res['company_name'] ?? 'บริษัท';
        });
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  // WORK SITES CRUD
  // ════════════════════════════════════════════

  Future<void> _loadWorkSites() async {
    final sites = await supabaseService.getWorkSites();
    if (mounted) setState(() => _workSites = sites);
  }

  Future<void> _saveSite({String? siteId}) async {
    final name = _siteNameController.text.trim();
    final lat = double.tryParse(_siteLatController.text.trim());
    final lng = double.tryParse(_siteLngController.text.trim());
    final address = _siteAddressController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ กรุณากรอกชื่อสาขา/บริษัท')),
      );
      return;
    }

    try {
      final payload = {
        'name': name,
        'gps_lat': lat,
        'gps_lng': lng,
        'gps_radius': _siteRadius,
        'address': address.isEmpty ? null : address,
      };

      if (siteId != null) {
        await supabase.from('work_sites').update(payload).eq('id', siteId);
      } else {
        await supabase.from('work_sites').insert(payload);
      }

      await _loadWorkSites();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              siteId != null ? '✅ แก้ไขสาขาแล้ว' : '✅ เพิ่มสาขาแล้ว',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    }
  }

  Future<void> _deleteSite(String siteId, String siteName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text("ยืนยันการลบ"),
            content: Text("ต้องการลบสาขา '$siteName' ใช่หรือไม่?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("ยกเลิก"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("ลบ", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (confirm == true) {
      try {
        await supabase.from('work_sites').delete().eq('id', siteId);
        await _loadWorkSites();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("ลบสาขาสำเร็จ")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      }
    }
  }

  void _openSiteForm({Map? site}) {
    if (site != null) {
      _siteNameController.text = site['name'] ?? '';
      _siteLatController.text = site['gps_lat']?.toString() ?? '';
      _siteLngController.text = site['gps_lng']?.toString() ?? '';
      _siteAddressController.text = site['address'] ?? '';
      _siteRadius = site['radius_meters'] ?? 100;
    } else {
      _siteNameController.clear();
      _siteLatController.clear();
      _siteLngController.clear();
      _siteAddressController.clear();
      _siteRadius = 100;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModalState) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: blue100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Text(
                          site != null
                              ? 'แก้ไขสาขา/บริษัท'
                              : 'เพิ่มสาขา/บริษัทลูกค้า',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: blue800,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _formLabel('ชื่อสาขา / บริษัทลูกค้า *'),
                        const SizedBox(height: 6),
                        _formTextField(
                          controller: _siteNameController,
                          hint: 'เช่น ร้าน ABC สาขาสยาม',
                          icon: Icons.business_rounded,
                        ),
                        const SizedBox(height: 12),

                        _formLabel('ที่อยู่ (ถ้ามี)'),
                        const SizedBox(height: 6),
                        _formTextField(
                          controller: _siteAddressController,
                          hint: 'เช่น 123 ถ.สุขุมวิท กรุงเทพฯ',
                          icon: Icons.place_outlined,
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _formLabel('ละติจูด'),
                                  const SizedBox(height: 6),
                                  _formTextField(
                                    controller: _siteLatController,
                                    hint: '13.7563',
                                    icon: Icons.explore_rounded,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _formLabel('ลองจิจูด'),
                                  const SizedBox(height: 6),
                                  _formTextField(
                                    controller: _siteLngController,
                                    hint: '100.5018',
                                    icon: Icons.explore_outlined,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            const Icon(
                              Icons.radio_button_checked,
                              size: 16,
                              color: teal400,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'รัศมีที่อนุญาต',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1a2a3a),
                              ),
                            ),
                            const Spacer(),
                            _counterBtn(Icons.remove, () {
                              if (_siteRadius > 50)
                                setModalState(() => _siteRadius -= 50);
                            }),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                '$_siteRadius ม.',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: blue800,
                                ),
                              ),
                            ),
                            _counterBtn(
                              Icons.add,
                              () => setModalState(() => _siteRadius += 50),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                () =>
                                    _saveSite(siteId: site?['id']?.toString()),
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: Text(
                              site != null ? 'บันทึกการแก้ไข' : 'เพิ่มสาขา',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blue600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  // ════════════════════════════════════════════
  // EMPLOYEE SCHEDULE
  // ════════════════════════════════════════════

  Future<Map?> _getEmployeeSchedule(String employeeId) async {
    try {
      return await supabase
          .from('employees')
          .select('work_start_time, late_threshold_minutes')
          .eq('id', employeeId)
          .single();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveEmployeeSchedule(
    String employeeId,
    TimeOfDay start,
    int lateMin,
  ) async {
    final timeStr =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:00';
    await supabase
        .from('employees')
        .update({
          'work_start_time': timeStr,
          'late_threshold_minutes': lateMin,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', employeeId);
  }

  // ════════════════════════════════════════════
  // EMPLOYEE DELETE
  // ════════════════════════════════════════════

   Future<void> deleteEmployee(String id, String name) async {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text("ยืนยันการลบ"),
      content: Text("ต้องการลบ $name ออกจากระบบถาวรใช่หรือไม่?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ยกเลิก"),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              // ← เปลี่ยนจาก supabaseService.deleteEmployee เป็น hard delete
              await supabase.from('employees').delete().eq('id', id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("ลบพนักงานสำเร็จ")),
                );
                loadData();
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            }
          },
          child: const Text("ลบถาวร", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
// ════════════════════════════════════════════
// EMPLOYEE EDIT
// ════════════════════════════════════════════

void _showEditEmployeeForm(Map emp) {
  final nameCtrl       = TextEditingController(text: emp['full_name'] ?? '');
  final usernameCtrl   = TextEditingController(text: emp['username'] ?? '');
  final emailCtrl      = TextEditingController(text: emp['email'] ?? '');
  final phoneCtrl      = TextEditingController(text: emp['phone'] ?? '');
  final deptCtrl       = TextEditingController(text: emp['department'] ?? '');
  final positionCtrl   = TextEditingController(text: emp['position'] ?? '');
  final empCodeCtrl    = TextEditingController(text: emp['employee_code'] ?? '');
  String? selectedSiteId = emp['work_site_id']?.toString();
  String  selectedStatus  = emp['status'] ?? 'active';
  String? selectedType    = emp['employment_type'];

  final empTypes = ['full_time', 'part_time', 'contract', 'intern'];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: ListView(
            shrinkWrap: true,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: blue100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
               Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: blue50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: blue100),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: blue600,
                                size: 16,
                              ),
                            ),
                          ),
                          const Icon(Icons.edit_rounded, color: blue600, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'แก้ไขข้อมูล — ${emp['full_name'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold, color: blue800,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
               SizedBox(height: 16),

              // ── ข้อมูลส่วนตัว ──────────────────────
              _editSectionLabel('ข้อมูลส่วนตัว'),
              const SizedBox(height: 8),
              _editField(nameCtrl,     'ชื่อ-นามสกุล *',  Icons.person_rounded),
              const SizedBox(height: 10),
              _editField(usernameCtrl, 'Username',          Icons.alternate_email),
              const SizedBox(height: 10),
              _editField(emailCtrl,    'Email',             Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              _editField(phoneCtrl,    'เบอร์โทรศัพท์',   Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 16),

              // ── ข้อมูลการทำงาน ─────────────────────
              _editSectionLabel('ข้อมูลการทำงาน'),
              const SizedBox(height: 8),
              _editField(deptCtrl,     'แผนก',            Icons.corporate_fare_rounded),
              const SizedBox(height: 10),
              _editField(positionCtrl, 'ตำแหน่ง',        Icons.military_tech_outlined),
              const SizedBox(height: 10),
              _editField(empCodeCtrl,  'รหัสพนักงาน',    Icons.tag_rounded),
              const SizedBox(height: 10),

              // สาขา / work site
              _editSectionLabel('สาขา / บริษัท'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: blue50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: blue100),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedSiteId,
                    isExpanded: true,
                    hint: const Text('ไม่ระบุสาขา',
                        style: TextStyle(fontSize: 13, color: gray400)),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF1a2a3a)),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— ไม่ระบุ —',
                            style: TextStyle(color: gray400)),
                      ),
                      ..._workSites.map((s) => DropdownMenuItem<String?>(
                            value: s['id'].toString(),
                            child: Text(s['name'] ?? '-'),
                          )),
                    ],
                    onChanged: (v) => setModal(() => selectedSiteId = v),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ประเภทการจ้าง
              _editSectionLabel('ประเภทการจ้าง'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: blue50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: blue100),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedType,
                    isExpanded: true,
                    hint: const Text('ไม่ระบุ',
                        style: TextStyle(fontSize: 13, color: gray400)),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF1a2a3a)),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('— ไม่ระบุ —',
                              style: TextStyle(color: gray400))),
                      ...empTypes.map((t) => DropdownMenuItem<String?>(
                            value: t,
                            child: Text(t),
                          )),
                    ],
                    onChanged: (v) => setModal(() => selectedType = v),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // สถานะ
              _editSectionLabel('สถานะพนักงาน'),
              const SizedBox(height: 8),
              Row(
                children: ['active', 'inactive'].map((s) {
                  final active = selectedStatus == s;
                  final isActive = s == 'active';
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setModal(() => selectedStatus = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: EdgeInsets.only(right: s == 'active' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: active
                              ? (isActive ? teal400 : red400)
                              : (isActive ? teal50 : red50),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive ? teal400 : red400,
                            width: active ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            isActive ? '✓ Active' : '✗ Inactive',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? Colors.white
                                  : (isActive ? teal400 : red400),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ── Save button ────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('❌ กรุณากรอกชื่อ-นามสกุล')),
                      );
                      return;
                    }
                    try {
                      await supabase.from('employees').update({
                        'full_name':       name,
                        'username':        usernameCtrl.text.trim().isEmpty
                            ? null
                            : usernameCtrl.text.trim(),
                        'email':           emailCtrl.text.trim().isEmpty
                            ? null
                            : emailCtrl.text.trim(),
                        'phone':           phoneCtrl.text.trim().isEmpty
                            ? null
                            : phoneCtrl.text.trim(),
                        'department':      deptCtrl.text.trim().isEmpty
                            ? null
                            : deptCtrl.text.trim(),
                        'position':        positionCtrl.text.trim().isEmpty
                            ? null
                            : positionCtrl.text.trim(),
                        'employee_code':   empCodeCtrl.text.trim().isEmpty
                            ? null
                            : empCodeCtrl.text.trim(),
                        'work_site_id':    selectedSiteId,
                        'employment_type': selectedType,
                        'status':          selectedStatus,
                        'updated_at':      DateTime.now().toIso8601String(),
                      }).eq('id', emp['id']);

                      await loadData();
                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('✅ แก้ไขข้อมูลพนักงานแล้ว')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('❌ Error: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text(
                    'บันทึกการแก้ไข',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// helper widgets สำหรับ edit form
Widget _editSectionLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 2),
  child: Text(text,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: blue800)),
);

Widget _editField(
  TextEditingController ctrl,
  String hint,
  IconData icon, {
  TextInputType keyboardType = TextInputType.text,
}) =>
    TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: gray400),
        prefixIcon: Icon(icon, size: 16, color: blue400),
        filled: true,
        fillColor: blue50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: blue100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: blue100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: blue600, width: 1.5),
        ),
      ),
    );

  // ════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════

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

  String _getSiteName(String? siteId) {
    if (siteId == null) return '-';
    final site = _workSites.firstWhere(
      (s) => s['id'].toString() == siteId,
      orElse: () => <String, dynamic>{},
    );
    return site['name'] ?? '-';
  }

  List get _filteredAttendance {
    final now = DateTime.now();
    return attendance.where((r) {
      if (_selectedSiteFilter != null &&
          r['employees']?['work_site_id']?.toString() != _selectedSiteFilter)
        return false;
      final workDate = r['work_date']?.toString() ?? '';
      if (workDate.isEmpty) return false;
      try {
        final dt = DateTime.parse(workDate);
        if (_attendanceFilterIndex == 0) {
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day;
        } else if (_attendanceFilterIndex == 1) {
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          return !dt.isBefore(
                DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day),
              ) &&
              !dt.isAfter(
                DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day),
              );
        } else {
          return dt.year == now.year && dt.month == now.month;
        }
      } catch (_) {
        return false;
      }
    }).toList();
  }

  List get _homeFilteredAttendance {
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

  List get _filteredEmployees {
    return employees.where((emp) {
      if (_selectedSiteFilter != null &&
          emp['work_site_id']?.toString() != _selectedSiteFilter)
        return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (emp['full_name'] ?? '').toString().toLowerCase();
        final username = (emp['username'] ?? '').toString().toLowerCase();
        final dept = (emp['department'] ?? '').toString().toLowerCase();
        return name.contains(q) || username.contains(q) || dept.contains(q);
      }
      return true;
    }).toList();
  }

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body:
          isLoading
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
                        _buildSitesTab(),
                        _buildScheduleTab(),
                      ],
                    ),
                  ),
                ],
              ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton:
          (_currentNavIndex == 0 || _currentNavIndex == 1)
              ? FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddEmployeeUI()),
                  ).then((_) => loadData());
                },
                backgroundColor: blue600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.person_add_rounded,
                  color: Colors.white,
                ),
              )
              : _currentNavIndex == 3
              ? FloatingActionButton(
                onPressed: () => _openSiteForm(),
                backgroundColor: teal400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.add_business_rounded,
                  color: Colors.white,
                ),
              )
              : _currentNavIndex == 4
              ? FloatingActionButton(
                // ← เพิ่ม
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ShiftManagementUI()),
                    ).then((_) => loadData()),
                backgroundColor: const Color(0xFF1D9E75),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add_alarm_rounded, color: Colors.white),
              )
              : null,
    );
  }

   Widget _buildScheduleTab() {
  final menuItems = [
    {
      'title': 'Shift Templates',
      'subtitle': 'จัดการกะงาน เวลาเข้า-ออก',
      'icon': Icons.schedule_rounded,
      'color': blue600,
      'bg': blue50,
      'onTap': () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ShiftManagementUI()))
          .then((_) => loadData()),
    },
    {
      'title': 'ตารางประจำ (Weekly Pattern)',
      'subtitle': 'ตั้งวันทำงานรายสัปดาห์ของพนักงาน',
      'icon': Icons.calendar_view_week_rounded,
      'color': teal400,
      'bg': teal50,
      'onTap': () => _pickEmployeeForSchedule(),
    },
    {
      'title': 'ปฏิทินตารางงาน',
      'subtitle': 'ดูภาพรวมและจัดการ Override รายวัน',
      'icon': Icons.calendar_month_rounded,
      'color': amber400,
      'bg': amber50,
      'onTap': () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ScheduleCalendarUI()))
          .then((_) => loadData()),
    },
  ];

  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [blue800, blue600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('จัดการกะงาน',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${_workSites.length} สาขา · พนักงาน ${employees.length} คน',
                style: const TextStyle(color: blue100, fontSize: 12)),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Menu items
      ...menuItems.map((item) => GestureDetector(
        onTap: item['onTap'] as VoidCallback,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: blue100),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: item['bg'] as Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item['icon'] as IconData,
                    color: item['color'] as Color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['title'] as String,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1a2a3a))),
                    const SizedBox(height: 3),
                    Text(item['subtitle'] as String,
                        style: const TextStyle(
                            fontSize: 11, color: gray400)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: item['color'] as Color),
            ],
          ),
        ),
      )),
    ],
  );
}

  Widget _scheduleQuickBtn(String label, IconData icon, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [blue800, blue600]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ─── HEADER ──────────────────────────────────────────────
  Widget _buildHeader() {
    final presentCount =
        attendance.where((r) => r['checkin_time'] != null).length;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "ยินดีต้อนรับ",
                      style: TextStyle(
                        color: Color.fromARGB(255, 255, 255, 255),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'OpMatch Admin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    onPressed: () => _openNotificationCenter(),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.white,
                    ),
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$_unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pushAndRemoveUntil(
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
                  child: const Icon(
                    Icons.logout,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDaySummary(),
        ],
      ),
    );
  }

  Widget _siteFilterChip(String? siteId, String label) {
    final active = _selectedSiteFilter == siteId;
    return GestureDetector(
      onTap: () => setState(() => _selectedSiteFilter = siteId),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? blue600 : blue50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : blue600,
          ),
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
      {'icon': Icons.business_rounded, 'label': 'สาขา'},
      {'icon': Icons.calendar_month_rounded, 'label': 'กะงาน'},
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: active ? blue50 : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          items[i]['icon'] as IconData,
                          color: active ? blue600 : gray400,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i]['label'] as String,
                        style: TextStyle(
                          fontSize: 9,
                          color: active ? blue600 : gray400,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
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

  // ════════════════════════════════════════════
  // TAB: HOME
  // ════════════════════════════════════════════

  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await loadData();
        await _loadLeaveData(); // ← เพิ่ม
      },
      color: blue600,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCalendarCard(),
          const SizedBox(height: 16),
          _buildSectionTitle('รายชื่อวันที่เลือก'),
          const SizedBox(height: 8),
          ..._homeFilteredAttendance.map((r) => _buildAttendanceCard(r)),
          if (_homeFilteredAttendance.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'ไม่มีข้อมูลวันที่เลือก',
                  style: TextStyle(color: gray400),
                ),
              ),
            ),
          _buildLeaveSection(), // ← เพิ่ม
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    final thaiMonths = [
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    final buddhistYear = _focusedMonth.year + 543;
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final today = DateTime.now();

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
          Row(
            children: [
              Text(
                '${thaiMonths[_focusedMonth.month - 1]} $buddhistYear',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: blue800,
                ),
              ),
              const Spacer(),
              _calNavBtn(Icons.chevron_left, () {
                setState(
                  () =>
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month - 1,
                        1,
                      ),
                );
              }),
              const SizedBox(width: 6),
              _calNavBtn(Icons.chevron_right, () {
                setState(
                  () =>
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month + 1,
                        1,
                      ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children:
                ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส']
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: const TextStyle(
                              fontSize: 11,
                              color: gray400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 6),
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
              final isToday =
                  today.year == _focusedMonth.year &&
                  today.month == _focusedMonth.month &&
                  today.day == day;
              final isSelected =
                  _selectedDate.year == _focusedMonth.year &&
                  _selectedDate.month == _focusedMonth.month &&
                  _selectedDate.day == day;
              final isLate = lateSet.contains(day);
              final isPresent = presentSet.contains(day);

              return GestureDetector(
                onTap:
                    () => setState(
                      () =>
                          _selectedDate = DateTime(
                            _focusedMonth.year,
                            _focusedMonth.month,
                            day,
                          ),
                    ),
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isSelected
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
                          color:
                              isSelected
                                  ? Colors.white
                                  : isToday
                                  ? blue600
                                  : const Color(0xFF1a2a3a),
                          fontWeight:
                              isSelected || isToday
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

  Widget _calNavBtn(IconData icon, VoidCallback onTap) => GestureDetector(
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

  Widget _legendDot(Color color, String label) => Row(
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: gray400)),
    ],
  );

   Widget _buildDaySummary() {
  final filtered = _homeFilteredAttendance;
  final presentCount = filtered
      .where((r) => r['checkin_time'] != null && r['late'] != true)
      .length;
  final lateCount = filtered.where((r) => r['late'] == true).length;

  // ลบบรรทัดเดิมออก: final absentCount = employees.length - filtered.length;
  // ใส่แทนด้วยนี้ ↓
  final checkedInIds = filtered
      .map((r) => (r['employees'] as Map?)?['id']?.toString())
      .whereType<String>()
      .toSet();
  final absentCount = employees.where((emp) {
    final empId = emp['id'].toString();
    return _shouldWorkToday(empId) && !checkedInIds.contains(empId);
  }).length;

    final now = DateTime.now();
    final thaiDays = [
      'อาทิตย์',
      'จันทร์',
      'อังคาร',
      'พุธ',
      'พฤหัสบดี',
      'ศุกร์',
      'เสาร์',
    ];
    final thaiMonths = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final dateLabel =
        'วัน${thaiDays[now.weekday % 7]}ที่ ${now.day} ${thaiMonths[now.month - 1]} ${now.year + 543}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // วันที่ label
        Row(
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
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _summaryChip(
              'มาแล้ว',
              '$presentCount',
              teal400,
              teal50,
              const Color(0xFF9FE1CB),
            ),
            const SizedBox(width: 8),
            _summaryChip(
              'สาย',
              '$lateCount',
              amber400,
              amber50,
              const Color(0xFFFAC775),
            ),
            const SizedBox(width: 8),
            _summaryChip(
              'ขาด',
              '$absentCount',
              red400,
              red50,
              const Color(0xFFF7C1C1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryChip(
    String label,
    String num,
    Color textColor,
    Color bgColor2,
    Color iconBg,
  ) {
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
            Text(
              num,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 11, color: gray400)),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // TAB: EMPLOYEES
  // ════════════════════════════════════════════

  Widget _buildEmployeesTab() {
    final filtered = _filteredEmployees;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: blue100),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: gray400, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1a2a3a),
                    ),
                    decoration: const InputDecoration(
                      hintText: 'ค้นหาชื่อ, username, แผนก...',
                      hintStyle: TextStyle(color: gray400, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _searchQuery = ''),
                    child: const Icon(Icons.close, color: gray400, size: 18),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: _buildSectionTitle(
            _searchQuery.isEmpty
                ? 'พนักงานทั้งหมด (${employees.length} คน)'
                : 'ผลการค้นหา (${filtered.length} คน)',
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              _siteFilterChip(null, 'ทั้งหมด'),
              ..._workSites.map(
                (s) => _siteFilterChip(s['id'].toString(), s['name']),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadData,
            color: blue600,
            child:
                filtered.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: gray400),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty
                                ? 'ไม่มีข้อมูลพนักงาน'
                                : 'ไม่พบ "$_searchQuery"',
                            style: TextStyle(color: gray400),
                          ),
                        ],
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _buildEmployeeCard(filtered[i]),
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
    final siteName = _getSiteName(emp['work_site_id']?.toString());

    return GestureDetector(
      onTap: () => _showEmployeeProfile(emp),
      child: Container(
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
              child:
                  profileUrl.isNotEmpty
                      ? Image.network(
                        profileUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => _empAvatarFallback(initials),
                        loadingBuilder:
                            (_, child, progress) =>
                                progress == null
                                    ? child
                                    : _empAvatarFallback(initials),
                      )
                      : _empAvatarFallback(initials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF1a2a3a),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${emp['username'] ?? '-'} · ${emp['department'] ?? '-'}',
                    style: const TextStyle(fontSize: 11, color: gray400),
                  ),
                  if (siteName != '-') ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 10, color: teal400),
                        const SizedBox(width: 2),
                        Text(
                          siteName,
                          style: const TextStyle(
                            fontSize: 10,
                            color: teal400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
             // เดิม

// ใหม่ → เพิ่มปุ่ม edit ไว้ด้านบน
Column(
  children: [
    Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: isActive ? teal400 : gray400,
        shape: BoxShape.circle,
      ),
    ),
    const SizedBox(height: 6),
    GestureDetector(
      onTap: () => _showEditEmployeeForm(emp),          // ← ใหม่
      child: const Icon(Icons.edit_outlined, color: blue600, size: 20),
    ),
    const SizedBox(height: 6),
    GestureDetector(
      onTap: () => deleteEmployee(emp['id'], name),
      child: const Icon(Icons.delete_outline, color: red400, size: 20),
    ),
  ],
),
          ],
        ),
      ),
    );
  }

  void _showEmployeeProfile(Map emp) async {
    final empId = emp['id']?.toString() ?? '';
    final empAttendance =
        attendance
            .where(
              (r) =>
                  (r['employees'] as Map?)?['id']?.toString() == empId ||
                  r['employee_id']?.toString() == empId,
            )
            .toList();

    Map? schedule;
    if (empId.isNotEmpty) schedule = await _getEmployeeSchedule(empId);

    TimeOfDay currentStart = _defaultWorkStart;
    int currentLateMin = _defaultLateThreshold;
    if (schedule != null) {
      final parts = (schedule['work_start_time'] as String).split(':');
      currentStart = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
      currentLateMin = schedule['late_threshold_minutes'] ?? 15;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _EmployeeProfileSheet(
            emp: emp,
            empAttendance: empAttendance,
            initStart: currentStart,
            initLateMin: currentLateMin,
            workSites: _workSites,
            getImageUrl: _getImageUrl,
            formatTime: _formatTime,
            formatDate: _formatDate,
            getSiteName: _getSiteName,
            onSaveSchedule: (start, lateMin) async {
              await _saveEmployeeSchedule(empId, start, lateMin);
              await loadData();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ บันทึกเวลาเข้างานพนักงานแล้ว'),
                  ),
                );
                _showEmployeeProfile(
                  employees.firstWhere((e) => e['id'].toString() == empId),
                );
              }
            },
          ),
    );
  }

  // ════════════════════════════════════════════
  // TAB: ATTENDANCE
  // ════════════════════════════════════════════

  Widget _buildAttendanceTab() {
    final labels = ['วันนี้', 'สัปดาห์นี้', 'เดือนนี้'];
    final filtered = _filteredAttendance;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: List.generate(labels.length, (i) {
              final active = i == _attendanceFilterIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _attendanceFilterIndex = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? blue600 : blue50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : blue600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _siteFilterChip(null, 'ทั้งหมด'),
              ..._workSites.map(
                (s) => _siteFilterChip(s['id'].toString(), s['name']),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${filtered.length} รายการ',
                style: const TextStyle(
                  fontSize: 12,
                  color: gray400,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'สาย ${filtered.where((r) => r['late'] == true).length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: amber400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadData,
            color: blue600,
            child:
                filtered.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: gray400),
                          const SizedBox(height: 8),
                          Text(
                            'ไม่มีข้อมูล Attendance',
                            style: TextStyle(color: gray400),
                          ),
                        ],
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _buildAttendanceCard(filtered[i]),
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
    final siteName = _getSiteName(empData?['work_site_id']?.toString());

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
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isLate ? amber400 : blue800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFF1a2a3a),
                        ),
                      ),
                      Text(
                        workDate,
                        style: const TextStyle(fontSize: 11, color: gray400),
                      ),
                      if (siteName != '-')
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 10,
                              color: teal400,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              siteName,
                              style: const TextStyle(
                                fontSize: 10,
                                color: teal400,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$checkIn › $checkOut',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: blue800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isLate ? amber50 : teal50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLate ? 'สาย' : 'ปกติ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isLate ? amber400 : teal400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (record['checkin_photo'] != null &&
              record['checkin_photo'].toString().isNotEmpty)
            _buildPhotoRow('Check In', _getImageUrl(record['checkin_photo'])),
          if (record['checkout_photo'] != null &&
              record['checkout_photo'].toString().isNotEmpty)
            _buildPhotoRow('Check Out', _getImageUrl(record['checkout_photo'])),
          if (record['checkin_lat'] != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 13, color: blue400),
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
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: blue600,
              ),
            ),
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
                loadingBuilder:
                    (_, child, progress) =>
                        progress == null
                            ? child
                            : Container(
                              height: 100,
                              color: gray50,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: blue400,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                errorBuilder:
                    (_, __, ___) => Container(
                      height: 100,
                      color: gray50,
                      child: const Center(
                        child: Icon(Icons.image_not_supported, color: gray400),
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // TAB: SITES
  // ════════════════════════════════════════════

  Widget _buildSitesTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadWorkSites();
        await loadData();
      },
      color: blue600,
      child:
          _workSites.isEmpty
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: blue50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.business_rounded,
                        size: 48,
                        color: blue400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ยังไม่มีสาขา/บริษัทลูกค้า',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: blue800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'กด + เพื่อเพิ่มสาขาหรือบริษัทลูกค้า',
                      style: TextStyle(fontSize: 12, color: gray400),
                    ),
                  ],
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _workSites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _buildSiteCard(_workSites[i]),
              ),
    );
  }

  Widget _buildSiteCard(Map site) {
    final siteId = site['id']?.toString();
    final siteName = site['name'] ?? 'ไม่ระบุชื่อ';
    final address = site['address'] ?? '';
    final lat = site['gps_lat'];
    final lng = site['gps_lng'];
    final radius = site['radius_meters'] ?? 100;

    final siteEmployees =
        employees
            .where((e) => e['work_site_id']?.toString() == siteId)
            .toList();
    final empCount = siteEmployees.length;

    final today = DateTime.now();
    final todayCheckins =
        attendance.where((r) {
          final workDate = r['work_date']?.toString() ?? '';
          if (workDate.isEmpty) return false;
          try {
            final dt = DateTime.parse(workDate);
            final empSite =
                (r['employees'] as Map?)?['work_site_id']?.toString();
            return dt.year == today.year &&
                dt.month == today.month &&
                dt.day == today.day &&
                empSite == siteId;
          } catch (_) {
            return false;
          }
        }).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [blue800, blue600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (address.isNotEmpty)
                        Text(
                          address,
                          style: const TextStyle(color: blue100, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _openSiteForm(site: site),
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  onPressed: () => _deleteSite(siteId!, siteName),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.white70,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _siteStat(
                  Icons.people_rounded,
                  '$empCount คน',
                  'พนักงาน',
                  blue600,
                  blue50,
                ),
                const SizedBox(width: 8),
                _siteStat(
                  Icons.login_rounded,
                  '$todayCheckins',
                  'เช็คอินวันนี้',
                  teal400,
                  teal50,
                ),
                const SizedBox(width: 8),
                _siteStat(
                  Icons.radio_button_checked,
                  '$radius ม.',
                  'รัศมี GPS',
                  amber400,
                  amber50,
                ),
              ],
            ),
          ),
          if (lat != null && lng != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: blue50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 13, color: blue400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Lat ${(lat as num).toStringAsFixed(5)}  ·  Lng ${(lng as num).toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: blue600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final url = 'https://www.google.com/maps?q=$lat,$lng';
                        await launchUrl(Uri.parse(url));
                      },
                      child: const Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: blue400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (siteEmployees.isNotEmpty) ...[
            const Divider(height: 1, color: blue100),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  const Text(
                    'พนักงานในสาขา',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: blue800,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showSiteEmployeeList(site, siteEmployees),
                    child: const Text(
                      'ดูทั้งหมด',
                      style: TextStyle(
                        fontSize: 11,
                        color: blue600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 60,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                scrollDirection: Axis.horizontal,
                itemCount: siteEmployees.take(6).length,
                itemBuilder: (_, i) {
                  final emp = siteEmployees[i];
                  final name = emp['full_name'] ?? '-';
                  final initials =
                      name.length >= 2 ? name.substring(0, 2) : name;
                  final profileUrl = _getImageUrl(emp['profile_photo']);
                  return GestureDetector(
                    onTap: () => _showEmployeeProfile(emp),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child:
                                profileUrl.isNotEmpty
                                    ? Image.network(
                                      profileUrl,
                                      width: 36,
                                      height: 36,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (_, __, ___) => _miniAvatar(initials),
                                    )
                                    : _miniAvatar(initials),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            name.split(' ').first,
                            style: const TextStyle(fontSize: 9, color: gray400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _siteStat(
    IconData icon,
    String value,
    String label,
    Color color,
    Color bg,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 9, color: gray400)),
          ],
        ),
      ),
    );
  }

  Widget _miniAvatar(String initials) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: blue50,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: blue800,
        ),
      ),
    ),
  );

  void _showSiteEmployeeList(Map site, List siteEmployees) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder:
                (_, controller) => Container(
                  decoration: const BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: blue100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.business_rounded,
                              size: 18,
                              color: blue600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                site['name'] ?? '-',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: blue800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: blue50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${siteEmployees.length} คน',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: blue600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: blue100),
                      Expanded(
                        child: ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.all(16),
                          itemCount: siteEmployees.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder:
                              (_, i) => _buildEmployeeCard(siteEmployees[i]),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  // ════════════════════════════════════════════
  // SHARED HELPER WIDGETS
  // ════════════════════════════════════════════

  Widget _formLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      color: gray400,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _formTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: gray400),
        prefixIcon: Icon(icon, size: 16, color: blue400),
        filled: true,
        fillColor: blue50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: blue100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: blue100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: blue600, width: 1.5),
        ),
      ),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: blue50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: blue600),
    ),
  );

  Widget _empAvatarFallback(String initials) => Container(
    width: 44,
    height: 44,
    color: blue50,
    child: Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: blue800,
          fontSize: 14,
        ),
      ),
    ),
  );

  Widget _buildSectionTitle(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: blue800,
    ),
  );

  void _showImageDialog(String url, String title) {
    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed:
                            () =>
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Icon(Icons.image_not_supported, size: 48),
                        ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _makePhoneCall(String phone) async {
    if (phone.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(launchUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถโทรออกได้: $e')));
      }
    }
  }

  void _pickEmployeeForSchedule() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: blue100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'เลือกพนักงาน',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: blue800,
                    ),
                  ),
                ),
                Expanded(
                  child:
                      employees.isEmpty
                          ? Center(
                            child: Text(
                              'ไม่มีข้อมูลพนักงาน',
                              style: TextStyle(color: gray400),
                            ),
                          )
                          : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                            itemCount: employees.length,
                            itemBuilder: (_, idx) {
                              final emp = employees[idx];
                              final name = emp['full_name'] ?? 'ไม่ระบุ';
                              final dept = emp['department'] ?? '-';
                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showEmployeeSchedule(emp);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: blue100),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: blue50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          name.isNotEmpty ? name[0] : '?',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: blue600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: blue800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              dept,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: gray400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 14,
                                        color: blue600,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
    );
  }

  void _showEmployeeSchedule(Map employee) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: blue100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.arrow_back, color: blue600),
                        padding: EdgeInsets.zero,
                      ),
                      Expanded(
                        child: Text(
                          'ตารางการทำงาน - ${employee['full_name'] ?? 'ไม่ระบุ'}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: blue800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder(
                    future: _getEmployeeSchedule(employee['id']),
                    builder: (_, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: blue600),
                        );
                      }
                      final schedule = snapshot.data;
                      final startTime =
                          schedule?['work_start_time'] ?? '08:00:00';
                      final lateMin = schedule?['late_threshold_minutes'] ?? 15;
                      final startParts = (startTime as String).split(':');
                      final start = TimeOfDay(
                        hour: int.parse(startParts[0]),
                        minute: int.parse(startParts[1]),
                      );

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: blue100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ข้อมูลตารางการทำงาน',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: blue800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text(
                                      'เวลาเริ่มงาน:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF1a2a3a),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: blue600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text(
                                      'ผ่อนผัน:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF1a2a3a),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$lateMin นาที',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: blue600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showEditEmployeeSchedule(
                                  employee['id'],
                                  start,
                                  lateMin,
                                );
                              },
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text(
                                'แก้ไขตารางการทำงาน',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blue600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => WeeklyScheduleUI(
                                          employee: employee,
                                        ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.calendar_view_week_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'ตั้งวันทำงาน (Pattern รายสัปดาห์)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: blue600,
                                side: BorderSide(color: blue100),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showEditEmployeeSchedule(String empId, TimeOfDay start, int lateMin) {
    late TimeOfDay editStart;
    late int editLateMin;
    editStart = start;
    editLateMin = lateMin;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModalState) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: blue100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const Text(
                          'แก้ไขตารางการทำงาน',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: blue800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _formLabel('เวลาเริ่มงาน'),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: editStart,
                            );
                            if (t != null) setModalState(() => editStart = t);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: blue100),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: blue600,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${editStart.hour.toString().padLeft(2, '0')}:${editStart.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: blue800,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: gray400,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.radio_button_checked,
                              size: 16,
                              color: teal400,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'ผ่อนผัน',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1a2a3a),
                              ),
                            ),
                            const Spacer(),
                            _counterBtn(Icons.remove, () {
                              if (editLateMin > 5)
                                setModalState(() => editLateMin -= 5);
                            }),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                '$editLateMin นาที',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: blue800,
                                ),
                              ),
                            ),
                            _counterBtn(
                              Icons.add,
                              () => setModalState(() => editLateMin += 5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                await _saveEmployeeSchedule(
                                  empId,
                                  editStart,
                                  editLateMin,
                                );
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '✅ บันทึกตารางการทำงานแล้ว',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('❌ Error: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: const Text(
                              'บันทึกการเปลี่ยนแปลง',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blue600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  Widget _buildLeaveSection() {
    if (_leaveData.isEmpty) return const SizedBox();

    // group by employee
    final Map<String, Map<String, dynamic>> leaveMap = {};
    for (final row in _leaveData) {
      final empId = row['employee_id'].toString();
      final empData = row['employees'] as Map?;
      final name = empData?['full_name'] ?? '-';
      final photo = empData?['profile_photo'];

      leaveMap.putIfAbsent(
        empId,
        () => {'name': name, 'photo': photo, 'count': 0},
      );
      leaveMap[empId]!['count'] = (leaveMap[empId]!['count'] as int) + 1;
    }

    final sortedList =
        leaveMap.values.toList()
          ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    final now = DateTime.now();
    final thaiMonths = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.beach_access_rounded, size: 16, color: red400),
            const SizedBox(width: 8),
            Text(
              'วันลาเดือน ${thaiMonths[now.month - 1]} ${now.year + 543}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: blue800,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: red50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_leaveData.length} วัน',
                style: const TextStyle(
                  fontSize: 12,
                  color: red400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...sortedList.map((item) {
          final name = item['name'] as String;
          final count = item['count'] as int;
          final photo = item['photo'];
          final initials = name.length >= 2 ? name.substring(0, 2) : name;
          final profileUrl = _getImageUrl(photo?.toString());

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: blue100),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child:
                      profileUrl.isNotEmpty
                          ? Image.network(
                            profileUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => _empAvatarFallback(initials),
                          )
                          : _empAvatarFallback(initials),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1a2a3a),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: count >= 3 ? red50 : amber50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          count >= 3
                              ? red400.withOpacity(0.3)
                              : amber400.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.beach_access_rounded,
                        size: 13,
                        color: count >= 3 ? red400 : amber400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$count วัน',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: count >= 3 ? red400 : amber400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// EMPLOYEE PROFILE BOTTOM SHEET
// ════════════════════════════════════════════════════════════

class _EmployeeProfileSheet extends StatefulWidget {
  final Map emp;
  final List empAttendance;
  final TimeOfDay initStart;
  final int initLateMin;
  final List workSites;
  final String Function(String?) getImageUrl;
  final String Function(String?) formatTime;
  final String Function(String?) formatDate;
  final String Function(String?) getSiteName;
  final Future<void> Function(TimeOfDay, int) onSaveSchedule;

  const _EmployeeProfileSheet({
    required this.emp,
    required this.empAttendance,
    required this.initStart,
    required this.initLateMin,
    required this.workSites,
    required this.getImageUrl,
    required this.formatTime,
    required this.formatDate,
    required this.getSiteName,
    required this.onSaveSchedule,
  });

  @override
  State<_EmployeeProfileSheet> createState() => _EmployeeProfileSheetState();
}

class _EmployeeProfileSheetState extends State<_EmployeeProfileSheet> {
  static const Color blue800 = Color(0xFF0C447C);
  static const Color blue600 = Color(0xFF185FA5);
  static const Color blue400 = Color(0xFF378ADD);
  static const Color blue100 = Color(0xFFB5D4F4);
  static const Color blue50 = Color(0xFFE6F1FB);
  static const Color teal400 = Color(0xFF1D9E75);
  static const Color teal50 = Color(0xFFE1F5EE);
  static const Color amber400 = Color(0xFFBA7517);
  static const Color amber50 = Color(0xFFFAEEDA);
  static const Color gray400 = Color(0xFF888780);

  late TimeOfDay _workStart;
  late int _lateMin;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _workStart = widget.initStart;
    _lateMin = widget.initLateMin;
  }

  String get _lateTimeStr {
    final total = _workStart.hour * 60 + _workStart.minute + _lateMin;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  int get _totalDays => widget.empAttendance.length;
  int get _lateDays =>
      widget.empAttendance.where((r) => r['late'] == true).length;
  int get _normalDays => _totalDays - _lateDays;
  double get _attendanceRate =>
      _totalDays == 0 ? 0 : (_normalDays / _totalDays * 100);

  @override
  Widget build(BuildContext context) {
    final emp = widget.emp;
    final name = emp['full_name'] ?? '-';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;
    final profileUrl = widget.getImageUrl(emp['profile_photo']);
    final siteName = widget.getSiteName(emp['work_site_id']?.toString());

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder:
          (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF0F5FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: blue100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [blue800, blue600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child:
                                profileUrl.isNotEmpty
                                    ? Image.network(
                                      profileUrl,
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (_, __, ___) =>
                                              _avatarFallback(initials, 64),
                                    )
                                    : _avatarFallback(initials, 64),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (emp['position'] != null)
                                  Text(
                                    emp['position'],
                                    style: const TextStyle(
                                      color: blue100,
                                      fontSize: 12,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    _profileBadge(
                                      emp['department'] ?? '-',
                                      Icons.corporate_fare,
                                    ),
                                    if (siteName != '-')
                                      _profileBadge(
                                        siteName,
                                        Icons.location_on,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  emp['status'] == 'active'
                                      ? teal50
                                      : const Color(0xFFF1EFE8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              emp['status'] == 'active' ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    emp['status'] == 'active'
                                        ? teal400
                                        : gray400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _profileStat(
                            '$_totalDays',
                            'วันทำงาน',
                            Colors.white,
                            Colors.white.withOpacity(0.15),
                          ),
                          const SizedBox(width: 8),
                          _profileStat(
                            '$_normalDays',
                            'มาตรงเวลา',
                            Colors.white,
                            Colors.white.withOpacity(0.15),
                          ),
                          const SizedBox(width: 8),
                          _profileStat(
                            '$_lateDays',
                            'มาสาย',
                            Colors.white,
                            Colors.white.withOpacity(0.15),
                          ),
                          const SizedBox(width: 8),
                          _profileStat(
                            '${_attendanceRate.toStringAsFixed(0)}%',
                            'อัตราตรงเวลา',
                            Colors.white,
                            Colors.white.withOpacity(0.15),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader('ข้อมูลส่วนตัว', Icons.person_rounded),
                const SizedBox(height: 8),
                _infoCard([
                  _infoRow(Icons.badge_outlined, 'ชื่อ-นามสกุล', name),
                  if (emp['username'] != null)
                    _infoRow(
                      Icons.alternate_email,
                      'Username',
                      emp['username'],
                    ),
                  if (emp['email'] != null)
                    _infoRow(Icons.email_outlined, 'Email', emp['email']),
                  if (emp['phone'] != null)
                    _infoRow(
                      Icons.phone_outlined,
                      'เบอร์โทร',
                      emp['phone'],
                      trailing: GestureDetector(
                        onTap: () async {
                          final uri = Uri(scheme: 'tel', path: emp['phone']);
                          await launchUrl(uri);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 25,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: teal50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone, size: 12, color: teal400),
                              SizedBox(width: 4),
                              Text(
                                'โทร',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: teal400,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                _sectionHeader('ข้อมูลการทำงาน', Icons.work_rounded),
                const SizedBox(height: 8),
                _infoCard([
                  if (emp['department'] != null)
                    _infoRow(
                      Icons.corporate_fare_rounded,
                      'แผนก',
                      emp['department'],
                    ),
                  if (emp['position'] != null)
                    _infoRow(
                      Icons.military_tech_outlined,
                      'ตำแหน่ง',
                      emp['position'],
                    ),
                  if (emp['employee_code'] != null)
                    _infoRow(
                      Icons.tag_rounded,
                      'รหัสพนักงาน',
                      emp['employee_code'],
                    ),
                  if (emp['work_site_id'] != null)
                    _infoRow(
                      Icons.location_on_rounded,
                      'สาขา/บริษัท',
                      widget.getSiteName(emp['work_site_id']?.toString()),
                    ),
                  if (emp['employment_type'] != null)
                    _infoRow(
                      Icons.work_history_outlined,
                      'ประเภทการจ้าง',
                      emp['employment_type'],
                    ),
                  if (emp['start_date'] != null)
                    _infoRow(
                      Icons.calendar_today_outlined,
                      'วันที่เริ่มงาน',
                      _formatDisplayDate(emp['start_date']?.toString()),
                    ),
                ]),
                const SizedBox(height: 12),
                _sectionHeader('เวลาเข้างาน', Icons.access_time_rounded),
                const SizedBox(height: 8),
                _scheduleCard(),
                const SizedBox(height: 12),
                _sectionHeader(
                  'ประวัติการเข้างาน (${widget.empAttendance.length} รายการ)',
                  Icons.history_rounded,
                ),
                const SizedBox(height: 8),
                if (widget.empAttendance.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: blue100),
                    ),
                    child: const Center(
                      child: Text(
                        'ยังไม่มีประวัติการเข้างาน',
                        style: TextStyle(color: gray400),
                      ),
                    ),
                  )
                else
                  ...widget.empAttendance.map((r) => _attendanceHistoryRow(r)),
              ],
            ),
          ),
    );
  }

  String _formatDisplayDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year + 543}';
    } catch (_) {
      return iso;
    }
  }

  Widget _sectionHeader(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: blue600),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: blue800,
        ),
      ),
    ],
  );

  Widget _profileStat(String value, String label, Color textColor, Color bg) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: textColor.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _scheduleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'เวลาเริ่มงาน',
                style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _workStart,
                  );
                  if (t != null) setState(() => _workStart = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: blue50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: blue100),
                  ),
                  child: Text(
                    '${_workStart.hour.toString().padLeft(2, '0')}:${_workStart.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: blue800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'ผ่อนผัน',
                style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
              ),
              const Spacer(),
              _cBtn(Icons.remove, () {
                if (_lateMin >= 5) setState(() => _lateMin -= 5);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '$_lateMin นาที',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: blue800,
                  ),
                ),
              ),
              _cBtn(Icons.add, () => setState(() => _lateMin += 5)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: amber50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFAC775)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: amber400),
                const SizedBox(width: 8),
                Text(
                  'เช็คอินหลัง $_lateTimeStr ถือว่าสาย',
                  style: const TextStyle(fontSize: 11, color: amber400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _saving
                      ? null
                      : () async {
                        setState(() => _saving = true);
                        await widget.onSaveSchedule(_workStart, _lateMin);
                        setState(() => _saving = false);
                      },
              style: ElevatedButton.styleFrom(
                backgroundColor: blue600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              child:
                  _saving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : const Text(
                        'บันทึกเวลาเข้างาน',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceHistoryRow(Map r) {
    final isLate = r['late'] == true;
    final checkIn = widget.formatTime(r['checkin_time']);
    final checkOut = widget.formatTime(r['checkout_time']);
    final workDate = widget.formatDate(r['work_date']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: blue100),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 36,
            decoration: BoxDecoration(
              color: isLate ? amber400 : teal400,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workDate,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1a2a3a),
                  ),
                ),
                Text(
                  '$checkIn → $checkOut',
                  style: const TextStyle(fontSize: 11, color: gray400),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isLate ? amber50 : teal50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isLate ? 'สาย' : 'ปกติ',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isLate ? amber400 : teal400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: blue100),
    ),
    child: Column(
      children:
          rows
              .map(
                (w) => Column(
                  children: [
                    w,
                    if (rows.last != w)
                      const Divider(height: 1, indent: 46, color: blue100),
                  ],
                ),
              )
              .toList(),
    ),
  );

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(
      children: [
        Icon(icon, size: 16, color: blue400),
        const SizedBox(width: 10),

        Text(label, style: const TextStyle(fontSize: 12, color: gray400)),

        const Spacer(),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1a2a3a),
            ),
          ),
        ),

        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );

  Widget _profileBadge(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.white70),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    ),
  );

  Widget _avatarFallback(String initials, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.28,
        ),
      ),
    ),
  );

  Widget _cBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: blue50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: blue600),
    ),
  );
}

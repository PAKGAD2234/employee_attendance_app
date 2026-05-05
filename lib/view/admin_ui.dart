import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import 'add_employee_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
  String _timeAgo(String? isoString) {
  if (isoString == null || isoString.isEmpty) return 'ไม่ระบุเวลา';
  
  try {
    final DateTime dateTime = DateTime.parse(isoString).toLocal();
    final Duration diff = DateTime.now().difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'เมื่อครู่นี้';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} นาทีที่แล้ว';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ชั่วโมงที่แล้ว';
    } else if (diff.inDays == 1) {
      return 'เมื่อวานนี้';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} วันที่แล้ว';
    } else {
      // ถ้าเกิน 7 วัน ให้แสดงเป็นวันที่ปกติ (พ.ศ.)
      return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
    }
  } catch (e) {
    return 'รูปแบบเวลาผิดพลาด';
  }
}

  // ─── Attendance filter
  int _attendanceFilterIndex = 0; // 0=วันนี้ 1=สัปดาห์นี้ 2=เดือนนี้

  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  // ─── Notification settings
  bool _notifyCheckin = true;
  bool _notifyLate = true;
  bool _notifyCheckout = false;

  // ─── Work schedule defaults
  TimeOfDay _defaultWorkStart = const TimeOfDay(hour: 8, minute: 0);
  int _defaultLateThreshold = 15;

  // ─── GPS Zone
  double? _gpsLat;
  double? _gpsLng;
  int _gpsRadius = 100;
  String _companyName = 'บริษัท';
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();

  // ─── สีหลัก
  static const Color blue800  = Color(0xFF0C447C);
  static const Color blue600  = Color(0xFF185FA5);
  static const Color blue400  = Color(0xFF378ADD);
  static const Color blue100  = Color(0xFFB5D4F4);
  static const Color blue50   = Color(0xFFE6F1FB);
  static const Color teal400  = Color(0xFF1D9E75);
  static const Color teal50   = Color(0xFFE1F5EE);
  static const Color red400   = Color(0xFFE24B4A);
  static const Color red50    = Color(0xFFFCEBEB);
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
  _loadNotificationSettings();
  _loadDefaultSchedule();
  _loadGpsZone();
  _fetchNotifications();        // โหลดของเก่าก่อนทันที (badge จะขึ้นเลย)
  _subscribeNotifications();   // แล้วค่อย subscribe รับของใหม่รงนี้
}

@override
void dispose() {
  _notifChannel?.unsubscribe(); // ← เพิ่มตรงนี้
  _latController.dispose();
  _lngController.dispose();
  _companyNameController.dispose();
  super.dispose();
}
  // ── Realtime subscription ──
RealtimeChannel? _notifChannel;




void _subscribeNotifications() {
  // ยกเลิก channel เดิมก่อน (ถ้ามี) เพื่อป้องกันการจอง memory ซ้ำซ้อน
  _notifChannel?.unsubscribe();

  _notifChannel = supabase
      .channel('notifications')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        callback: (payload) {
          final data = payload.newRecord;
          final isLate = data['type'] == 'late';

          // 1. เช็ค settings: ถ้าตั้งค่าปิดแจ้งเตือนไว้ ให้หยุดทำงาน
          if (!isLate && !_notifyCheckin) return;
          if (isLate && !_notifyLate) return;

          

          // 3. อัปเดต UI ทันที
          loadData();            // โหลดข้อมูลหน้าหลักใหม่
          _fetchNotifications(); // โหลดรายการในกระดิ่งแจ้งเตือนใหม่
          
          // *** ห้ามเรียก _subscribeNotifications() ซ้ำที่นี่เด็ดขาด ***
          // เพราะมันจะสร้าง Channel ใหม่ทับไปเรื่อยๆ ทุกครั้งที่มีคนกดเช็คอิน
        },
      )
      .subscribe();
}
Future<void> _fetchNotifications() async {
  try {
    final data = await supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(20);

    if (mounted) { // เช็คว่าหน้าจอยังเปิดอยู่ไหมก่อน setState
      setState(() {
        _notifications = data;
         // เช็คทั้ง false และ null เผื่อ row เก่าที่ไม่มีค่า
        _unreadCount = data.where((n) {
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
  setState(() {
    _unreadCount = 0; // เคลียร์ตัวเลข Badge
  });

  // (Optionally) อัปเดตในฐานข้อมูลว่าอ่านแล้วทั้งหมด
  _markAllAsRead(); 

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            // Handle bar สำหรับลากปิด
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: gray400.withOpacity(0.3), 
                borderRadius: BorderRadius.circular(10)
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text("ศูนย์แจ้งเตือน", 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: blue800)),
            ),

            Expanded(
              child: _notifications.isEmpty 
                ? Center(child: Text("ไม่มีการแจ้งเตือนในขณะนี้", style: TextStyle(color: gray400)))
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
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)],
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
                              color: isLate ? red400 : teal400,
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
                              Text(_timeAgo(item['created_at']), 
                                  style: const TextStyle(fontSize: 10, color: gray400)),
                            ],
                          ),
                          trailing: (isLate && item['employee_phone'] != null)
                            ? IconButton(
                                icon: const Icon(Icons.phone_enabled_rounded, color: blue600, size: 20),
                                onPressed: () => _makePhoneCall(item['employee_phone']),
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

// ฟังก์ชันเสริมสำหรับเคลียร์สถานะอ่านแล้วใน DB (ถ้าต้องการ)
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

 void _showCheckinNotification({
  required String name,
  required String message,
  required String phone,
  required bool isLate,
}) {
  if (!mounted) return;

  // ใช้ showModalBottomSheet แบบไม่มี Overlay หนาๆ (Barrier) 
  showBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
      ),
      child: Row(
        children: [
          // ซ้าย: ไอคอน
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLate ? red50 : teal50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLate ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: isLate ? red400 : teal400,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // กลาง: ชื่อ + ข้อความ
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(message, style: const TextStyle(fontSize: 12, color: gray400), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // ขวา: ปุ่มโทร (ถ้าสาย) หรือปุ่มปิด
          if (isLate && phone.isNotEmpty)
            IconButton(
              onPressed: () => _makePhoneCall(phone),
              icon: const Icon(Icons.phone_forwarded, color: blue600),
            )
          else
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18, color: gray400),
            ),
        ],
      ),
    ),
  );

  // ตั้งเวลาให้ปิดตัวเองอัตโนมัติใน 5 วินาที
  Future.delayed(const Duration(seconds: 5), () {
    if (Navigator.canPop(context)) Navigator.pop(context);
  });
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final res = await supabase
          .from('notification_settings')
          .select()
          .eq('admin_id', 'admin')
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _notifyCheckin  = res['notify_on_checkin']  ?? true;
          _notifyLate     = res['notify_on_late']     ?? true;
          _notifyCheckout = res['notify_on_checkout'] ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveNotificationSettings() async {
    try {
      await supabase.from('notification_settings').upsert({
        'admin_id'          : 'admin',
        'notify_on_checkin' : _notifyCheckin,
        'notify_on_late'    : _notifyLate,
        'notify_on_checkout': _notifyCheckout,
        'updated_at'        : DateTime.now().toIso8601String(),
      }, onConflict: 'admin_id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ บันทึกการตั้งค่าแจ้งเตือนแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    }
  }

  Future<void> _loadDefaultSchedule() async {
    try {
      final res = await supabase
          .from('work_schedules')
          .select()
          .isFilter('employee_id', null)
          .maybeSingle();
      if (res != null && mounted) {
        final parts = (res['work_start_time'] as String).split(':');
        setState(() {
          _defaultWorkStart = TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          _defaultLateThreshold = res['late_threshold_minutes'] ?? 15;
        });
      }
    } catch (_) {}
  }

  /// แก้ไข: ใช้ delete + insert แทน upsert เพื่อรองรับ employee_id = null
  Future<void> _saveGlobalSchedule() async {
  final timeStr =
      '${_defaultWorkStart.hour.toString().padLeft(2, '0')}:${_defaultWorkStart.minute.toString().padLeft(2, '0')}:00';
  try {
    // ── อัปเดต employees ทุกคน ──
    await supabase.from('employees').update({
      'work_start_time'       : timeStr,
      'late_threshold_minutes': _defaultLateThreshold,
      'updated_at'            : DateTime.now().toIso8601String(),
    }).neq('id', '00000000-0000-0000-0000-000000000000'); // update ทุก row

    // ── บันทึก global default ลง work_schedules (employee_id = null) ──
    await supabase
        .from('work_schedules')
        .delete()
        .isFilter('employee_id', null);
    await supabase.from('work_schedules').insert({
      'employee_id'           : null,
      'work_start_time'       : timeStr,
      'late_threshold_minutes': _defaultLateThreshold,
      'updated_at'            : DateTime.now().toIso8601String(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ บันทึกเวลาเข้างานแล้ว')));
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }
}

  // ────────────────────────────────────────────
  // GPS ZONE
  // ────────────────────────────────────────────

  Future<void> _loadGpsZone() async {
    try {
      final res = await supabase
          .from('gps_zones')
          .select()
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _gpsLat      = (res['latitude'] as num?)?.toDouble();
          _gpsLng      = (res['longitude'] as num?)?.toDouble();
          _gpsRadius   = res['radius_meters'] ?? 100;
          _companyName = res['company_name'] ?? 'บริษัท';
          _latController.text = _gpsLat?.toString() ?? '';
          _lngController.text = _gpsLng?.toString() ?? '';
          _companyNameController.text = _companyName;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveGpsZone() async {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    final name = _companyNameController.text.trim();

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ กรุณากรอกละติจูด/ลองจิจูดให้ถูกต้อง')));
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ กรุณากรอกชื่อบริษัท')));
      return;
    }

    try {
      // ใช้ delete + insert เหมือนกัน เพราะมักมีแค่ 1 row
      await supabase.from('gps_zones').delete().neq('id', '00000000-0000-0000-0000-000000000000');
      await supabase.from('gps_zones').insert({
        'company_name'  : name,
        'latitude'      : lat,
        'longitude'     : lng,
        'radius_meters' : _gpsRadius,
        'updated_at'    : DateTime.now().toIso8601String(),
      });

      setState(() {
        _gpsLat      = lat;
        _gpsLng      = lng;
        _companyName = name;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ บันทึก GPS Zone แล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    }
  }

  // ────────────────────────────────────────────
  // EMPLOYEE SCHEDULE per-person
  // ────────────────────────────────────────────

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
    String employeeId, TimeOfDay start, int lateMin) async {
  final timeStr =
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:00';

  await supabase.from('employees').update({
    'work_start_time'       : timeStr,
    'late_threshold_minutes': lateMin,
    'updated_at'            : DateTime.now().toIso8601String(),
  }).eq('id', employeeId);
}

  // ════════════════════════════════════════════
  // AUTH
  // ════════════════════════════════════════════

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

  // ════════════════════════════════════════════
  // HELPER
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

  List get _filteredAttendance {
    final now = DateTime.now();
    return attendance.where((r) {
      final workDate = r['work_date']?.toString() ?? '';
      if (workDate.isEmpty) return false;
      try {
        final dt = DateTime.parse(workDate);
        if (_attendanceFilterIndex == 0) {
          return dt.year == now.year && dt.month == now.month && dt.day == now.day;
        } else if (_attendanceFilterIndex == 1) {
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          return !dt.isBefore(DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day)) &&
              !dt.isAfter(DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day));
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
  if (_searchQuery.isEmpty) return employees;
  final q = _searchQuery.toLowerCase();
  return employees.where((emp) {
    final name     = (emp['full_name']   ?? '').toString().toLowerCase();
    final username = (emp['username']    ?? '').toString().toLowerCase();
    final dept     = (emp['department']  ?? '').toString().toLowerCase();
    return name.contains(q) || username.contains(q) || dept.contains(q);
  }).toList();
}

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  // ─── HEADER ──────────────────────────────────────────────
  Widget _buildHeader() {
    final presentCount = attendance.where((r) => r['checkin_time'] != null).length;
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
        left: 20, right: 20, bottom: 20,
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
                    const Text("ยินดีต้อนรับ",
                        style: TextStyle(color: blue100, fontSize: 13)),
                    Text(
                      _companyName.isNotEmpty ? _companyName : 'Admin Dashboard',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              // ปุ่ม Notification
                  Stack(
                    children: [
                      IconButton(
                        onPressed: () => _openNotificationCenter(),
                        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                      ),
                      if (_unreadCount > 0)
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: Text('$_unreadCount', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
              GestureDetector(
                onTap: () {
                  Navigator.pushAndRemoveUntil(context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.logout, color: Colors.white, size: 20),
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
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: blue100, fontSize: 11)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? blue50 : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(items[i]['icon'] as IconData,
                            color: active ? blue600 : gray400, size: 22),
                      ),
                      const SizedBox(height: 3),
                      Text(items[i]['label'] as String,
                          style: TextStyle(
                              fontSize: 10,
                              color: active ? blue600 : gray400,
                              fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
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
          ..._homeFilteredAttendance.map((r) => _buildAttendanceCard(r)),
          if (_homeFilteredAttendance.isEmpty)
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

  Widget _buildCalendarCard() {
    final thaiMonths = [
      'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน',
      'พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม',
      'กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
    ];
    final buddhistYear = _focusedMonth.year + 543;
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final today = DateTime.now();

    final lateSet    = <int>{};
    final presentSet = <int>{};
    for (final r in attendance) {
      final workDate = r['work_date']?.toString() ?? '';
      if (workDate.isEmpty) continue;
      try {
        final dt = DateTime.parse(workDate);
        if (dt.year == _focusedMonth.year && dt.month == _focusedMonth.month) {
          if (r['late'] == true) { lateSet.add(dt.day); }
          else { presentSet.add(dt.day); }
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: blue800),
              ),
              const Spacer(),
              _calNavBtn(Icons.chevron_left, () {
                setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1));
              }),
              const SizedBox(width: 6),
              _calNavBtn(Icons.chevron_right, () {
                setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1));
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['อา','จ','อ','พ','พฤ','ศ','ส'].map((d) {
              return Expanded(
                child: Center(
                  child: Text(d,
                      style: const TextStyle(fontSize: 11, color: gray400, fontWeight: FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (_, idx) {
              if (idx < firstWeekday) return const SizedBox();
              final day = idx - firstWeekday + 1;
              final isToday = today.year == _focusedMonth.year &&
                  today.month == _focusedMonth.month && today.day == day;
              final isSelected = _selectedDate.year == _focusedMonth.year &&
                  _selectedDate.month == _focusedMonth.month && _selectedDate.day == day;
              final isLate    = lateSet.contains(day);
              final isPresent = presentSet.contains(day);

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, day));
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? blue600 : isToday ? blue50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text('$day',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : isToday ? blue600 : const Color(0xFF1a2a3a),
                            fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                          )),
                      if (!isSelected && (isLate || isPresent))
                        Positioned(
                          bottom: 3,
                          child: Container(
                            width: 4, height: 4,
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
          width: 30, height: 30,
          decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: blue600, size: 18),
        ),
      );

  Widget _legendDot(Color color, String label) => Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: gray400)),
        ],
      );

  Widget _buildDaySummary() {
    final filtered = _homeFilteredAttendance;
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

  Widget _summaryChip(String label, String num, Color textColor, Color bgColor2, Color iconBg) {
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
            Text(num, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
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
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _buildSectionTitle(
          _searchQuery.isEmpty
              ? 'พนักงานทั้งหมด (${employees.length} คน)'
              : 'ผลการค้นหา (${filtered.length} คน)',
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: loadData,
          color: blue600,
          child: filtered.isEmpty
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
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
    final isActive   = emp['status'] == 'active';
    final name       = emp['full_name'] ?? '-';
    final initials   = name.length >= 2 ? name.substring(0, 2) : name;
    final profileUrl = _getImageUrl(emp['profile_photo']);

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
              child: profileUrl.isNotEmpty
                  ? Image.network(profileUrl, width: 44, height: 44, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _empAvatarFallback(initials),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : _empAvatarFallback(initials))
                  : _empAvatarFallback(initials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1a2a3a))),
                  const SizedBox(height: 2),
                  Text('${emp['username'] ?? '-'} · ${emp['department'] ?? '-'}',
                      style: const TextStyle(fontSize: 11, color: gray400)),
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? teal400 : gray400,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 8),
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
    final empAttendance = attendance
        .where((r) =>
            (r['employees'] as Map?)?['id']?.toString() == empId ||
            r['employee_id']?.toString() == empId)
        .toList();

    Map? schedule;
    if (empId.isNotEmpty) schedule = await _getEmployeeSchedule(empId);

    TimeOfDay currentStart = _defaultWorkStart;
    int currentLateMin     = _defaultLateThreshold;
    if (schedule != null) {
      final parts = (schedule['work_start_time'] as String).split(':');
      currentStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      currentLateMin = schedule['late_threshold_minutes'] ?? 15;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeProfileSheet(
        emp          : emp,
        empAttendance: empAttendance,
        initStart    : currentStart,
        initLateMin  : currentLateMin,
        getImageUrl  : _getImageUrl,
        formatTime   : _formatTime,
        formatDate   : _formatDate,
        onSaveSchedule: (start, lateMin) async {
            await _saveEmployeeSchedule(empId, start, lateMin);
            await loadData(); // ← เพิ่ม
            if (mounted) {
              Navigator.pop(context); // ← ปิด sheet
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ บันทึกเวลาเข้างานพนักงานแล้ว')));
              // เปิด sheet ใหม่พร้อมข้อมูลล่าสุด
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
                      child: Text(labels[i],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active ? Colors.white : blue600)),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('${filtered.length} รายการ',
                  style: const TextStyle(fontSize: 12, color: gray400, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('สาย ${filtered.where((r) => r['late'] == true).length}',
                  style: const TextStyle(fontSize: 12, color: amber400, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadData,
            color: blue600,
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: gray400),
                        const SizedBox(height: 8),
                        Text('ไม่มีข้อมูล Attendance', style: TextStyle(color: gray400)),
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
    final empData  = record['employees'] as Map?;
    final isLate   = record['late'] == true;
    final checkIn  = _formatTime(record['checkin_time']);
    final checkOut = _formatTime(record['checkout_time']);
    final workDate = _formatDate(record['work_date']?.toString());
    final name     = empData?['full_name'] ?? 'Unknown';
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
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: isLate ? amber50 : blue50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13,
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
                              fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1a2a3a))),
                      Text(workDate, style: const TextStyle(fontSize: 11, color: gray400)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$checkIn › $checkOut',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: blue800)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLate ? amber50 : teal50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(isLate ? 'สาย' : 'ปกติ',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: isLate ? amber400 : teal400)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (record['checkin_photo'] != null && record['checkin_photo'].toString().isNotEmpty)
            _buildPhotoRow('Check In', _getImageUrl(record['checkin_photo'])),
          if (record['checkout_photo'] != null && record['checkout_photo'].toString().isNotEmpty)
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
            decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: blue600)),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showImageDialog(url, label),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(url, height: 100, width: double.infinity, fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(height: 100, color: gray50,
                          child: const Center(child: CircularProgressIndicator(color: blue400, strokeWidth: 2))),
                  errorBuilder: (_, __, ___) => Container(height: 100, color: gray50,
                      child: const Center(child: Icon(Icons.image_not_supported, color: gray400)))),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // TAB: SETTINGS
  // ════════════════════════════════════════════

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
                width: 50, height: 50,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14)),
                child: const Center(
                  child: Text('AD',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('admin@company.com', style: TextStyle(color: blue100, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildNotificationCard(),
        const SizedBox(height: 12),

        _buildGlobalScheduleCard(),
        const SizedBox(height: 12),

        // ─── GPS Zone (เพิ่มใหม่)
        _buildGpsZoneCard(),
        const SizedBox(height: 12),

        _settingsGroup([
          _settingsItem(Icons.logout_rounded, 'ออกจากระบบ', () {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (context) => LoginPage()));
          }, color: red400),
        ]),
      ],
    );
  }

  // ─── GPS Zone Card ────────────────────────────────────────
  Widget _buildGpsZoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: teal50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.location_on_rounded, color: teal400, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('กำหนด GPS Zone',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a2a3a))),
                      Text('พื้นที่อนุญาตให้เช็คอิน',
                          style: TextStyle(fontSize: 10, color: gray400)),
                    ],
                  ),
                ),
                // แสดงสถานะว่ามี GPS Zone หรือยัง
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _gpsLat != null ? teal50 : gray50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _gpsLat != null ? 'ตั้งค่าแล้ว' : 'ยังไม่ตั้งค่า',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: _gpsLat != null ? teal400 : gray400),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: blue100),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ชื่อบริษัท
                _gpsLabel('ชื่อบริษัท / สถานที่'),
                const SizedBox(height: 6),
                _gpsTextField(
                  controller: _companyNameController,
                  hint: 'เช่น บริษัท ABC จำกัด',
                  icon: Icons.business_rounded,
                ),
                const SizedBox(height: 14),

                // แสดงตัวอย่างชื่อที่จะขึ้นในหน้าจอพนักงาน
                if (_companyNameController.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: blue50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: blue100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.smartphone, size: 14, color: blue600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'พนักงานจะเห็น: "${_companyNameController.text}"',
                            style: const TextStyle(fontSize: 11, color: blue600),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // ละติจูด / ลองจิจูด
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _gpsLabel('ละติจูด (Latitude)'),
                          const SizedBox(height: 6),
                          _gpsTextField(
                            controller: _latController,
                            hint: 'เช่น 13.7563',
                            icon: Icons.explore_rounded,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _gpsLabel('ลองจิจูด (Longitude)'),
                          const SizedBox(height: 6),
                          _gpsTextField(
                            controller: _lngController,
                            hint: 'เช่น 100.5018',
                            icon: Icons.explore_outlined,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // รัศมี
                Row(
                  children: [
                    const Icon(Icons.radio_button_checked, size: 16, color: teal400),
                    const SizedBox(width: 8),
                    const Text('รัศมีที่อนุญาต',
                        style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a))),
                    const Spacer(),
                    _counterBtn(Icons.remove, () {
                      if (_gpsRadius > 50) setState(() => _gpsRadius -= 50);
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('$_gpsRadius เมตร',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold, color: blue800)),
                    ),
                    _counterBtn(Icons.add, () => setState(() => _gpsRadius += 50)),
                  ],
                ),
                const SizedBox(height: 10),

                // Info box
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: teal50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF9FE1CB)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: teal400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'พนักงานต้องอยู่ในรัศมี $_gpsRadius เมตร จากตำแหน่งที่กำหนดจึงจะเช็คอินได้',
                          style: const TextStyle(fontSize: 11, color: teal400),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // วิธีหาพิกัด
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: amber50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFAC775)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.tips_and_updates_outlined, size: 14, color: amber400),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'วิธีหาพิกัด: เปิด Google Maps → กด ค้างที่ตำแหน่งบริษัท → ระบบจะแสดงพิกัดให้คัดลอก',
                          style: TextStyle(fontSize: 11, color: amber400),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveGpsZone,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('บันทึก GPS Zone',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: teal400,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _gpsLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, color: gray400, fontWeight: FontWeight.w500),
      );

  Widget _gpsTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: gray400),
        prefixIcon: Icon(icon, size: 16, color: blue400),
        filled: true,
        fillColor: blue50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  // ─── Notification Card ────────────────────────────────────
  Widget _buildNotificationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.notifications_rounded, color: blue600, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('การแจ้งเตือน',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a2a3a))),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: blue100),
          _notifToggle(
            icon: Icons.login_rounded,
            label: 'แจ้งเมื่อพนักงานเช็คอิน',
            sub: 'รับแจ้งเตือนทุกครั้งที่มีการลงเวลาเข้างาน',
            value: _notifyCheckin,
            onChanged: (v) => setState(() => _notifyCheckin = v),
          ),
          _notifToggle(
            icon: Icons.warning_amber_rounded,
            label: 'แจ้งเมื่อพนักงานสาย',
            sub: 'รับแจ้งเตือนเมื่อมีการเช็คอินเกินเวลาที่กำหนด',
            value: _notifyLate,
            onChanged: (v) => setState(() => _notifyLate = v),
            iconColor: amber400, iconBg: amber50,
          ),
          _notifToggle(
            icon: Icons.logout_rounded,
            label: 'แจ้งเมื่อพนักงานเช็คเอาท์',
            sub: 'รับแจ้งเตือนทุกครั้งที่มีการลงเวลาออก',
            value: _notifyCheckout,
            onChanged: (v) => setState(() => _notifyCheckout = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveNotificationSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('บันทึกการตั้งค่าแจ้งเตือน',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notifToggle({
    required IconData icon, required String label, required String sub,
    required bool value, required ValueChanged<bool> onChanged,
    Color iconColor = blue600, Color iconBg = blue50,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1a2a3a))),
                Text(sub, style: const TextStyle(fontSize: 10, color: gray400)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: blue600),
        ],
      ),
    );
  }

  // ─── Global Schedule Card ─────────────────────────────────
  Widget _buildGlobalScheduleCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.access_time_rounded, color: blue600, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ตั้งเวลาเข้างาน (ค่าเริ่มต้น)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a2a3a))),
                      Text('ใช้กับพนักงานที่ไม่ได้ตั้งค่าแยก',
                          style: TextStyle(fontSize: 10, color: gray400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: blue100),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: blue400),
                    const SizedBox(width: 8),
                    const Text('เวลาเริ่มงาน', style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a))),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _defaultWorkStart);
                        if (t != null) setState(() => _defaultWorkStart = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: blue50, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: blue100),
                        ),
                        child: Text(
                          '${_defaultWorkStart.hour.toString().padLeft(2, '0')}:${_defaultWorkStart.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: blue800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: amber400),
                    const SizedBox(width: 8),
                    const Text('ผ่อนผันได้', style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a))),
                    const Spacer(),
                    Row(
                      children: [
                        _counterBtn(Icons.remove, () {
                          if (_defaultLateThreshold > 0) setState(() => _defaultLateThreshold -= 5);
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('$_defaultLateThreshold นาที',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: blue800)),
                        ),
                        _counterBtn(Icons.add, () => setState(() => _defaultLateThreshold += 5)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: amber50, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFAC775)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: amber400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'เช็คอินหลัง ${_defaultWorkStart.hour.toString().padLeft(2, '0')}:${(_defaultWorkStart.minute + _defaultLateThreshold).toString().padLeft(2, '0')} ถือว่าสาย',
                          style: const TextStyle(fontSize: 11, color: amber400),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveGlobalSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue600, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('บันทึกเวลาเข้างาน',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: blue600),
        ),
      );

  Widget _settingsGroup(List<Widget> items) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: blue100),
        ),
        child: Column(children: items),
      );

  Widget _settingsItem(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? const Color(0xFF1a2a3a);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                  color: color != null ? red50 : blue50,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color ?? blue600, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c))),
            Icon(Icons.chevron_right, color: gray400, size: 18),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════════

  Widget _empAvatarFallback(String initials) => Container(
        width: 44, height: 44, color: blue50,
        child: Center(
          child: Text(initials,
              style: const TextStyle(fontWeight: FontWeight.bold, color: blue800, fontSize: 14)),
        ),
      );

  Widget _buildSectionTitle(String title) => Text(title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: blue800));

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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Icon(Icons.image_not_supported, size: 48))),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _makePhoneCall(String phone) async {
  if (phone.isEmpty) return;
  final Uri launchUri = Uri(
    scheme: 'tel',
    path: phone,
  );
  try {
    await launchUrl(launchUri);  // ลบ canLaunchUrl ออก แล้วเรียก launchUrl ตรงๆ
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถโทรออกได้: $e')),
      );
    }
  }
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
  final String Function(String?) getImageUrl;
  final String Function(String?) formatTime;
  final String Function(String?) formatDate;
  final Future<void> Function(TimeOfDay, int) onSaveSchedule;

  const _EmployeeProfileSheet({
    required this.emp,
    required this.empAttendance,
    required this.initStart,
    required this.initLateMin,
    required this.getImageUrl,
    required this.formatTime,
    required this.formatDate,
    required this.onSaveSchedule,
  });

  @override
  State<_EmployeeProfileSheet> createState() => _EmployeeProfileSheetState();
}

class _EmployeeProfileSheetState extends State<_EmployeeProfileSheet> {
  static const Color blue800  = Color(0xFF0C447C);
  static const Color blue600  = Color(0xFF185FA5);
  static const Color blue400  = Color(0xFF378ADD);
  static const Color blue100  = Color(0xFFB5D4F4);
  static const Color blue50   = Color(0xFFE6F1FB);
  static const Color teal400  = Color(0xFF1D9E75);
  static const Color teal50   = Color(0xFFE1F5EE);
  static const Color amber400 = Color(0xFFBA7517);
  static const Color amber50  = Color(0xFFFAEEDA);
  static const Color gray400  = Color(0xFF888780);
  static const Color gray50   = Color(0xFFF1EFE8);

  late TimeOfDay _workStart;
  late int _lateMin;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _workStart = widget.initStart;
    _lateMin   = widget.initLateMin;
  }

  String get _lateTimeStr {
    final total = _workStart.hour * 60 + _workStart.minute + _lateMin;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final emp  = widget.emp;
    final name = emp['full_name'] ?? '-';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;
    final profileUrl = widget.getImageUrl(emp['profile_photo']);

    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF0F5FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: blue100, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [blue800, blue600],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: profileUrl.isNotEmpty
                        ? Image.network(profileUrl, width: 56, height: 56, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatarFallback(initials))
                        : _avatarFallback(initials),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        _profileBadge(emp['department'] ?? '-'),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: emp['status'] == 'active' ? teal50 : gray50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      emp['status'] == 'active' ? 'Active' : 'Inactive',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: emp['status'] == 'active' ? teal400 : gray400),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _infoCard([
              _infoRow(Icons.person_outline, 'ชื่อจริง', name),
              _infoRow(Icons.alternate_email, 'Username', emp['username'] ?? '-'),
              _infoRow(Icons.email_outlined, 'Email', emp['email'] ?? '-'),
              _infoRow(Icons.business_outlined, 'แผนก', emp['department'] ?? '-'),
            ]),
            const SizedBox(height: 16),
            _scheduleCard(),
            const SizedBox(height: 16),
            Text('ประวัติการเข้างาน (${widget.empAttendance.length} รายการ)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: blue800)),
            const SizedBox(height: 8),
            if (widget.empAttendance.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: blue100)),
                child: const Center(
                  child: Text('ยังไม่มีประวัติการเข้างาน',
                      style: TextStyle(color: gray400)),
                ),
              )
            else
              ...widget.empAttendance.take(20).map((r) => _attendanceHistoryRow(r)),
          ],
        ),
      ),
    );
  }

  Widget _scheduleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.access_time_rounded, size: 16, color: blue600),
              SizedBox(width: 8),
              Text('ตั้งเวลาเข้างานเฉพาะบุคคล',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: blue800)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('เวลาเริ่มงาน', style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a))),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _workStart);
                  if (t != null) setState(() => _workStart = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: blue50, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: blue100),
                  ),
                  child: Text(
                    '${_workStart.hour.toString().padLeft(2, '0')}:${_workStart.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: blue800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('ผ่อนผัน', style: TextStyle(fontSize: 13, color: Color(0xFF1a2a3a))),
              const Spacer(),
              _cBtn(Icons.remove, () { if (_lateMin >= 5) setState(() => _lateMin -= 5); }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('$_lateMin นาที',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: blue800)),
              ),
              _cBtn(Icons.add, () => setState(() => _lateMin += 5)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: amber50, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFAC775)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: amber400),
                const SizedBox(width: 8),
                Text('เช็คอินหลัง $_lateTimeStr ถือว่าสาย',
                    style: const TextStyle(fontSize: 11, color: amber400)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                await widget.onSaveSchedule(_workStart, _lateMin);
                setState(() => _saving = false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: blue600, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('บันทึกเวลาเข้างาน',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceHistoryRow(Map r) {
    final isLate   = r['late'] == true;
    final checkIn  = widget.formatTime(r['checkin_time']);
    final checkOut = widget.formatTime(r['checkout_time']);
    final workDate = widget.formatDate(r['work_date']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: blue100),
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 36,
            decoration: BoxDecoration(
              color: isLate ? amber400 : teal400, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(workDate,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a2a3a))),
                Text('$checkIn → $checkOut', style: const TextStyle(fontSize: 11, color: gray400)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isLate ? amber50 : teal50, borderRadius: BorderRadius.circular(6)),
            child: Text(isLate ? 'สาย' : 'ปกติ',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    color: isLate ? amber400 : teal400)),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: blue100),
        ),
        child: Column(children: rows),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 16, color: blue400),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 12, color: gray400)),
            const Spacer(),
            Flexible(
              child: Text(value, textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1a2a3a))),
            ),
          ],
        ),
      );

  Widget _profileBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      );

  Widget _avatarFallback(String initials) => Container(
        width: 56, height: 56, color: Colors.white.withOpacity(0.2),
        child: Center(
          child: Text(initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
      );

  Widget _cBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: blue600),
        ),
      );
}
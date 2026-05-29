import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduleCalendarUI extends StatefulWidget {
  final String? initialSiteId;
  final bool showOverrideButton;
  const ScheduleCalendarUI({
    super.key,
    this.initialSiteId,
    this.showOverrideButton = true,
  });

  @override
  State<ScheduleCalendarUI> createState() => _ScheduleCalendarUIState();
}

class _ScheduleCalendarUIState extends State<ScheduleCalendarUI>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List _employees = [];
  List _shifts = [];
  List _workSites = [];
  List _overrides = [];

  Map<String, Map<int, Map>> _weeklyMap = {};

  bool _isLoading = true;
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  String? _filterSiteId;
  String? _filterShiftId;

  late TabController _tabController;

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

  static const List<String> _dayShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];
  static const List<String> _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialSiteId != null) {
      _filterSiteId = widget.initialSiteId;
    }
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  // DATA
  // ════════════════════════════════════════════

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final year = _focusedMonth.year;
      final month = _focusedMonth.month;
      final firstDay = '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay =
          '$year-${month.toString().padLeft(2, '0')}-${DateTime(year, month + 1, 0).day.toString().padLeft(2, '0')}';

      final emps = await supabase
          .from('employees')
          .select('id, full_name, profile_photo, work_site_id, department')
          .eq('status', 'active')
          .neq('role', 'admin')
          .order('full_name');

      final shifts = await supabase
          .from('shift_templates')
          .select('*')
          .eq('is_active', true)
          .order('start_time');

      final sites =
          await supabase.from('work_sites').select().order('name');

      final overrides = await supabase
          .from('schedule_overrides')
          .select('*, employees(full_name, role), shift_templates(*), work_sites(name)')
          .gte('override_date', firstDay)
          .lte('override_date', lastDay)
          .not('employees.role', 'eq', 'admin')
          .order('override_date');

      final weeklies = await supabase
          .from('employee_weekly_schedules')
          .select('*, shift_templates(*), work_sites(name)')
          .isFilter('effective_until', null);

      final empsList = List<Map<String, dynamic>>.from(emps as List);
      final wMap = <String, Map<int, Map>>{};
      for (final row in (weeklies as List)) {
        final empId = row['employee_id'].toString();
        if (!empsList.any((e) => e['id'].toString() == empId)) continue;
        final dow = row['day_of_week'] as int;
        wMap.putIfAbsent(empId, () => {});
        wMap[empId]![dow] = row;
      }

      if (mounted) {
        setState(() {
          _employees = emps;
          _shifts = shifts;
          _workSites = sites;
          _overrides = overrides;
          _weeklyMap = wMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('โหลดข้อมูลล้มเหลว: $e', isError: true);
    }
  }

  Map? _getEffective(String empId, DateTime date) {
    final dateStr = _toDateStr(date);
    final dayOfWeek = date.weekday % 7;

    final ov = (_overrides as List).cast<Map?>().firstWhere(
          (o) =>
              o!['employee_id'].toString() == empId &&
              o['override_date'].toString() == dateStr,
          orElse: () => null,
        );
    if (ov != null) return {...ov, '_source': 'override'};

    final wk = _weeklyMap[empId]?[dayOfWeek];
    if (wk != null) return {...wk, '_source': 'weekly'};

    return null;
  }

  Color _scheduleColor(Map? sched) {
    if (sched == null) return gray400;
    final ovType = sched['override_type'];
    if (ovType == 'leave') return red400;
    final shift = sched['shift_templates'];
    if (shift == null) return gray400;
    var hex = shift['color'] ?? '#185FA5';
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  String _getImageUrl(String? val) {
    if (val == null || val.isEmpty) return '';
    if (val.startsWith('http')) return val;
    return supabase.storage.from('attendance').getPublicUrl(val);
  }

  List get _filteredEmployees {
    return _employees.where((emp) {
      if (_filterSiteId != null &&
          emp['work_site_id']?.toString() != _filterSiteId) return false;
      return true;
    }).toList();
  }

  List get _selectedDayOverrides {
    final dateStr = _toDateStr(_selectedDate);
    return _overrides
        .where((o) => o['override_date'].toString() == dateStr)
        .toList();
  }

  // ════════════════════════════════════════════
  // OVERRIDE CRUD
  // ════════════════════════════════════════════

  void _openOverrideForm({Map? existing, Map? employee}) {
    String? selectedEmpId =
        existing?['employee_id']?.toString() ?? employee?['id']?.toString();
    String? selectedShiftId = existing?['shift_template_id']?.toString();
    String? selectedSiteId = existing?['work_site_id']?.toString();
    String overrideType = existing?['override_type'] ?? 'special';
    final noteCtrl = TextEditingController(text: existing?['note'] ?? '');
    DateTime overrideDate = existing != null
        ? DateTime.parse(existing['override_date'])
        : _selectedDate;
    TimeOfDay? customStart;
    TimeOfDay? customEnd;
    if (existing?['custom_start_time'] != null) {
      customStart = _parseTime(existing!['custom_start_time']);
    }
    if (existing?['custom_end_time'] != null) {
      customEnd = _parseTime(existing!['custom_end_time']);
    }
    bool useCustomTime = customStart != null;

    final typeOptions = [
      {'value': 'special', 'label': 'งานพิเศษ', 'icon': Icons.star_rounded, 'color': blue600, 'bg': blue50},
      {'value': 'ot', 'label': 'OT', 'icon': Icons.more_time_rounded, 'color': amber400, 'bg': amber50},
      {'value': 'leave', 'label': 'ลา/หยุด', 'icon': Icons.beach_access_rounded, 'color': red400, 'bg': red50},
      {'value': 'substitute', 'label': 'แทนคน', 'icon': Icons.swap_horiz_rounded, 'color': teal400, 'bg': teal50},
    ];

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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: gray400),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: blue100, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: amber50, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.edit_calendar_rounded, color: amber400, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        existing != null ? 'แก้ไข Override' : 'เพิ่ม Override รายวัน',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: blue800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _label('วันที่'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: overrideDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setModal(() => overrideDate = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: blue50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: blue100),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: blue600),
                          const SizedBox(width: 10),
                          Text(
                            '${overrideDate.day.toString().padLeft(2, '0')}/${overrideDate.month.toString().padLeft(2, '0')}/${overrideDate.year + 543}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold, color: blue800),
                          ),
                          const Spacer(),
                          const Text('เปลี่ยน', style: TextStyle(fontSize: 11, color: blue400)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label('พนักงาน *'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: blue50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: blue100),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selectedEmpId,
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
                        hint: const Text('เลือกพนักงาน',
                            style: TextStyle(color: gray400, fontSize: 13)),
                        isExpanded: true,
                        items: _employees
                            .map((e) => DropdownMenuItem<String>(
                                  value: e['id'].toString(),
                                  child: Text(e['full_name'] ?? '-'),
                                ))
                            .toList(),
                        onChanged: (v) => setModal(() => selectedEmpId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label('ประเภท'),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.6,
                    children: typeOptions.map((opt) {
                      final isSelected = overrideType == opt['value'];
                      final c = opt['color'] as Color;
                      final bg = opt['bg'] as Color;
                      return GestureDetector(
                        onTap: () => setModal(() => overrideType = opt['value'] as String),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? bg : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: isSelected ? c : blue100,
                                width: isSelected ? 1.5 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(opt['icon'] as IconData,
                                  size: 16, color: isSelected ? c : gray400),
                              const SizedBox(height: 3),
                              Text(opt['label'] as String,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected ? c : gray400,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  if (overrideType != 'leave') ...[
                    _label('กะงาน'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          label: 'ไม่กำหนด',
                          selected: selectedShiftId == null,
                          color: gray400,
                          bg: gray50,
                          onTap: () => setModal(() => selectedShiftId = null),
                        ),
                        ..._shifts.map((s) {
                          var hex = s['color'] ?? '#185FA5';
                          final h = hex.replaceAll('#', '');
                          final c = Color(int.parse('FF$h', radix: 16));
                          return _chip(
                            label: s['name'],
                            sublabel:
                                '${_formatTime(s['start_time'])}-${_formatTime(s['end_time'])}',
                            selected: selectedShiftId == s['id'].toString(),
                            color: c,
                            bg: c.withOpacity(0.1),
                            onTap: () {
                              setModal(() {
                                selectedShiftId = s['id'].toString();
                                customStart = _parseTime(s['start_time'] ?? '09:00');
                                customEnd = _parseTime(s['end_time'] ?? '18:00');
                              });
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => setModal(() => useCustomTime = !useCustomTime),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: useCustomTime ? blue50 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: useCustomTime ? blue600 : blue100),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              useCustomTime
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: useCustomTime ? blue600 : gray400,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text('กำหนดเวลาเฉพาะวันนี้',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: useCustomTime ? blue800 : gray400,
                                    fontWeight: useCustomTime
                                        ? FontWeight.w600
                                        : FontWeight.normal)),
                          ],
                        ),
                      ),
                    ),
                    if (useCustomTime) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('เริ่ม'),
                                const SizedBox(height: 6),
                                _timeTile(
                                  time: customStart ??
                                      const TimeOfDay(hour: 9, minute: 0),
                                  color: teal400,
                                  bg: teal50,
                                  icon: Icons.login_rounded,
                                  onTap: () async {
                                    final t = await showTimePicker(
                                        context: ctx,
                                        initialTime: customStart ??
                                            const TimeOfDay(hour: 9, minute: 0));
                                    if (t != null) setModal(() => customStart = t);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('เลิก'),
                                const SizedBox(height: 6),
                                _timeTile(
                                  time: customEnd ??
                                      const TimeOfDay(hour: 18, minute: 0),
                                  color: red400,
                                  bg: red50,
                                  icon: Icons.logout_rounded,
                                  onTap: () async {
                                    final t = await showTimePicker(
                                        context: ctx,
                                        initialTime: customEnd ??
                                            const TimeOfDay(hour: 18, minute: 0));
                                    if (t != null) setModal(() => customEnd = t);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _label('สาขา / บริษัท'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: blue50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: blue100),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: selectedSiteId,
                          dropdownColor: Colors.white,
                          style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
                          hint: const Text('ใช้ค่าปัจจุบัน',
                              style: TextStyle(color: gray400, fontSize: 12)),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                                value: null,
                                child: Text('ใช้ค่าปัจจุบัน',
                                    style: TextStyle(color: gray400))),
                            ..._workSites.map((s) => DropdownMenuItem<String>(
                                  value: s['id'].toString(),
                                  child: Text(s['name']),
                                )),
                          ],
                          onChanged: (v) => setModal(() => selectedSiteId = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _label('หมายเหตุ'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1a2a3a)),
                    decoration: InputDecoration(
                      hintText: 'เช่น ออกบูธ Central World',
                      hintStyle: const TextStyle(color: gray400, fontSize: 12),
                      filled: true,
                      fillColor: blue50,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: blue100)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: blue100)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: blue600, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      if (existing != null) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _deleteOverride(existing['id'].toString()),
                            icon: const Icon(Icons.delete_outline, size: 14, color: red400),
                            label: const Text('ลบ',
                                style: TextStyle(color: red400, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: red400),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => _saveOverride(
                            ctx: ctx,
                            existingId: existing?['id']?.toString(),
                            empId: selectedEmpId,
                            date: overrideDate,
                            shiftId: overrideType == 'leave' ? null : selectedShiftId,
                            siteId: selectedSiteId,
                            overrideType: overrideType,
                            customStart: useCustomTime ? customStart : null,
                            customEnd: useCustomTime ? customEnd : null,
                            note: noteCtrl.text.trim(),
                          ),
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: Text(
                            existing != null ? 'บันทึกการแก้ไข' : 'บันทึก Override',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveOverride({
    required BuildContext ctx,
    String? existingId,
    required String? empId,
    required DateTime date,
    required String? shiftId,
    required String? siteId,
    required String overrideType,
    TimeOfDay? customStart,
    TimeOfDay? customEnd,
    required String note,
  }) async {
    if (empId == null) {
      _snack('กรุณาเลือกพนักงาน', isError: true);
      return;
    }

    final payload = {
      'employee_id': empId,
      'override_date': _toDateStr(date),
      'shift_template_id': shiftId,
      'work_site_id': siteId,
      'override_type': overrideType,
      'custom_start_time': customStart != null ? _toTimeStr(customStart) : null,
      'custom_end_time': customEnd != null ? _toTimeStr(customEnd) : null,
      'note': note.isEmpty ? null : note,
    };

    try {
      if (existingId != null) {
        await supabase.from('schedule_overrides').update(payload).eq('id', existingId);
      } else {
        await supabase
            .from('schedule_overrides')
            .upsert(payload, onConflict: 'employee_id,override_date');
      }
      await _loadAll();
      if (mounted) {
        Navigator.pop(ctx);
        _snack('✅ บันทึก Override สำเร็จ');
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _deleteOverride(String id) async {
    try {
      await supabase.from('schedule_overrides').delete().eq('id', id);
      await _loadAll();
      if (mounted) {
        Navigator.pop(context);
        _snack('ลบ Override สำเร็จ');
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  void _confirmShiftChanges({
    required BuildContext ctx,
    required DateTime date,
    required Map<String, String?> newAssignments,
    required Map<String, String?> originalAssignments,
    required Map<String, String?> shiftSiteAssignments,
  }) async {
    // Find all changes
    final List<Map<String, dynamic>> changes = [];
    final Map<String, String?> replacedEmployees = {}; // Track who was replaced

    for (final shiftId in newAssignments.keys) {
      final oldEmpId = originalAssignments[shiftId];
      final newEmpId = newAssignments[shiftId];

      // Check if there's a change
      if (oldEmpId != newEmpId) {
        final shift = _shifts.firstWhere(
          (s) => s['id'].toString() == shiftId,
          orElse: () => <String, dynamic>{},   // ← เพิ่ม type
        );
        
        String? oldEmpName;
        if (oldEmpId != null) {
          final oldEmp = _employees.firstWhere(
            (e) => e['id'].toString() == oldEmpId,
            orElse: () => <String, dynamic>{},   // ← เพิ่ม type
          );
          oldEmpName = oldEmp['full_name'];
        }

        String? newEmpName;
        if (newEmpId != null) {
          final newEmp = _employees.firstWhere(
            (e) => e['id'].toString() == newEmpId,
            orElse: () => <String, dynamic>{},   // ← เพิ่ม type
          );
          newEmpName = newEmp['full_name'];
        }

        changes.add({
          'shiftId': shiftId,
          'shiftName': shift['name'] ?? '-',
          'oldEmpId': oldEmpId,
          'oldEmpName': oldEmpName ?? 'ไม่มีคน',
          'newEmpId': newEmpId,
          'newEmpName': newEmpName ?? 'ไม่มีคน',
        });

        // Track replaced employees
        if (oldEmpId != null) {
          replacedEmployees[oldEmpId] = oldEmpName;
        }
      }
    }

    // If no changes, just proceed
    if (changes.isEmpty) {
      await _saveShiftAssignments(
        ctx: ctx,
        date: date,
        shiftAssignments: newAssignments,
        shiftSiteAssignments: shiftSiteAssignments,
        replacedEmployees: {},
      );
      return;
    }

    // Show confirmation dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: amber50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_rounded, color: amber400, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ยืนยันการเปลี่ยนพนักงาน',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: blue800,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: blue50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_rounded, size: 16, color: blue600),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'พนักงานที่โดนเปลี่ยนจะถูกตั้งเป็น "ลา/หยุด" โดยอัตโนมัติ',
                        style: TextStyle(fontSize: 12, color: blue600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...changes.map((change) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: blue100),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          change['shiftName'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: blue800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'เดิม',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: gray400,
                                    ),
                                  ),
                                  Text(
                                    change['oldEmpName'],
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: red400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: blue400,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'ใหม่',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: gray400,
                                    ),
                                  ),
                                  Text(
                                    change['newEmpName'],
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: teal400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(color: gray400, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _saveShiftAssignments(
                ctx: ctx,
                date: date,
                shiftAssignments: newAssignments,
                shiftSiteAssignments: shiftSiteAssignments,
                replacedEmployees: replacedEmployees,
              );
            },
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text(
              'ยืนยัน',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: blue600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveShiftAssignments({
    required BuildContext ctx,
    required DateTime date,
    required Map<String, String?> shiftAssignments,
    required Map<String, String?> shiftSiteAssignments,
    required Map<String, String?> replacedEmployees,
  }) async {
    try {
      for (final entry in shiftAssignments.entries) {
        final shiftId = entry.key;
        final empId = entry.value;

        if (empId == null) {
          await supabase
              .from('schedule_overrides')
              .delete()
              .eq('override_date', _toDateStr(date))
              .eq('shift_template_id', shiftId);
        } else {
           // ลบ override เดิมของ shift นี้ก่อน
          await supabase
              .from('schedule_overrides')
              .delete()
              .eq('override_date', _toDateStr(date))
              .eq('shift_template_id', shiftId);
          await supabase.from('schedule_overrides').upsert(
            {
              'employee_id': empId,
              'override_date': _toDateStr(date),
              'shift_template_id': shiftId,
              'work_site_id': shiftSiteAssignments[shiftId],
              'override_type': 'special',
              'note': 'จัดกะโดยแอดมิน',
            },
            onConflict: 'employee_id,override_date',
          );
        }
      }

      // Create leave overrides for replaced employees
      for (final entry in replacedEmployees.entries) {
        final replacedEmpId = entry.key;
        // ลบ override เดิมของคนนี้วันนี้ก่อน
        await supabase
            .from('schedule_overrides')
            .delete()
            .eq('override_date', _toDateStr(date))
            .eq('employee_id', replacedEmpId);
        // แล้วค่อย insert leave ใหม่
        await supabase.from('schedule_overrides').insert({
          'employee_id': replacedEmpId,
          'override_date': _toDateStr(date),
          'override_type': 'leave',
          'note': 'เปลี่ยนไปทำกะอื่น',
        });
      }

      await _loadAll();
      if (mounted) {
        Navigator.pop(ctx);
        _snack('✅ บันทึกกะวันที่ ${date.day}/${date.month} สำเร็จ');
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_tabController.index == 1) {
              _tabController.animateTo(0);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        backgroundColor: blue800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('ปฏิทินตารางงาน',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'ภาพรวม Calendar'),
            Tab(text: 'Override รายวัน'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: blue600))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCalendarTab(),
                _buildOverrideTab(),
              ],
            ),
      floatingActionButton: widget.showOverrideButton
          ? FloatingActionButton.extended(
              onPressed: () => _openOverrideForm(),
              backgroundColor: amber400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('เพิ่ม Override',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  // ════════════════════════════════════════════
  // TAB 1 — CALENDAR OVERVIEW
  // ════════════════════════════════════════════

  Widget _buildCalendarTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: blue600,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _buildMonthNavigator(),
          const SizedBox(height: 12),
          _buildFilterRow(),
          const SizedBox(height: 12),
          _buildCalendarGrid(),
          const SizedBox(height: 16),
          if (_filteredEmployees.isNotEmpty) ...[
            _buildSectionTitle(
              '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year + 543} — ${_filteredEmployees.length} คน',
            ),
            const SizedBox(height: 10),
            ..._filteredEmployees.map((emp) => _buildEmployeeDayCard(emp, _selectedDate)),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [blue800, blue600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left, () {
            setState(() {
              _focusedMonth =
                  DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
              _loadAll();
            });
          }),
          Expanded(
            child: Center(
              child: Text(
                '${_thaiMonths[_focusedMonth.month - 1]} ${_focusedMonth.year + 543}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          _navBtn(Icons.chevron_right, () {
            setState(() {
              _focusedMonth =
                  DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
              _loadAll();
            });
          }),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: blue100),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _filterSiteId,
          isExpanded: true,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: blue600),
          style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.business_rounded, size: 16, color: blue400),
                  SizedBox(width: 8),
                  Text('เลือกสาขา',
                      style: TextStyle(color: blue800, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            ..._workSites.map((s) => DropdownMenuItem<String>(
                  value: s['id'].toString(),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 16, color: teal400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s['name'] ?? '-',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF1a2a3a))),
                      ),
                    ],
                  ),
                )),
          ],
          onChanged: (v) => setState(() => _filterSiteId = v),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue100),
      ),
      child: Column(
        children: [
          Row(
            children: _dayShort
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: const TextStyle(
                                fontSize: 12,
                                color: gray400,
                                fontWeight: FontWeight.w500)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.35,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (_, idx) {
              if (idx < firstWeekday) return const SizedBox();
              final day = idx - firstWeekday + 1;
              final date =
                  DateTime(_focusedMonth.year, _focusedMonth.month, day);
              final isToday = today.year == date.year &&
                  today.month == date.month &&
                  today.day == date.day;
              final isSelected = _selectedDate.year == date.year &&
                  _selectedDate.month == date.month &&
                  _selectedDate.day == date.day;

              final workingEmps = _filteredEmployees.where((emp) {
                final sched = _getEffective(emp['id'].toString(), date);
                return sched != null && sched['override_type'] != 'leave';
              }).toList();

              // ── กดพื้นที่ว่าง = แค่ select วัน ──────────────────────
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedDate = date),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? blue50 : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? blue600
                          : isToday
                              ? blue600
                              : blue100,
                      width: isSelected || isToday ? 1.5 : 0.5,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── ตัวเลขวัน — กดเปิด ShiftAssigner ──────────
                      GestureDetector(
                        onTap: () {
                          setState(() => _selectedDate = date);
                          if (widget.showOverrideButton) _openShiftAssigner(date);
                        },
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? blue600
                                  : isToday
                                      ? blue600
                                      : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected || isToday
                                    ? Colors.white
                                    : const Color(0xFF1a2a3a),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // ── chip ชื่อพนักงาน — กดเปิด ShiftAssigner ────
                      ...workingEmps.take(3).map((emp) {
                        final sched = _getEffective(emp['id'].toString(), date);
                        final shift = sched?['shift_templates'];
                        final shiftName = shift?['name'] ?? '';
                        final startStr = sched?['custom_start_time'] != null
                            ? _formatTime(sched!['custom_start_time'])
                            : (shift != null
                                ? _formatTime(shift['start_time'])
                                : null);
                        final endStr = sched?['custom_end_time'] != null
                            ? _formatTime(sched!['custom_end_time'])
                            : (shift != null
                                ? _formatTime(shift['end_time'])
                                : null);
                        final name = (emp['full_name'] ?? '-').toString();
                        final firstName = name.split(' ').first;

                        Color shiftColor = blue400;
                        if (shift?['color'] != null) {
                          final h =
                              (shift!['color'] as String).replaceAll('#', '');
                          shiftColor = Color(int.parse('FF$h', radix: 16));
                        }

                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedDate = date);
                            if (widget.showOverrideButton) _openShiftAssigner(date);
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 2),
                            decoration: BoxDecoration(
                              color: shiftColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                 Text(
                                      firstName,
                                      style: TextStyle(
                                        fontSize: _responsiveFontSize(context, mobile: 6, desktop: 10),
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1a2a3a),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                if (startStr != null && startStr != '--:--')
                                  Text(
                                    '$startStr-${endStr ?? ''}',
                                    style: TextStyle(
                                      fontSize: _responsiveFontSize(context, mobile: 5, desktop: 8),
                                      color: shiftColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                else if (shiftName.isNotEmpty)
                                  Text(
                                    shiftName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: shiftColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (workingEmps.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Text(
                            '+${workingEmps.length - 3} คน',
                            style: const TextStyle(
                              fontSize: 9,
                              color: blue400,
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
              _legendDot(blue400, 'จำนวนคน'),
              const SizedBox(width: 12),
              _legendDot(amber400, 'มี Override'),
              const SizedBox(width: 12),
              _legendDot(blue600, 'วันที่เลือก'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeDayCard(Map emp, DateTime date) {
    final sched = _getEffective(emp['id'].toString(), date);
    final isOff = sched == null || sched['override_type'] == 'leave';
    final isOverride = sched?['_source'] == 'override';
    final shift = sched?['shift_templates'];
    final schedColor = _scheduleColor(sched);

    final profileUrl = _getImageUrl(emp['profile_photo']?.toString());
    final name = emp['full_name'] ?? '-';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;

    final startStr = sched?['custom_start_time'] != null
        ? _formatTime(sched!['custom_start_time'])
        : (shift != null ? _formatTime(shift['start_time']) : null);
    final endStr = sched?['custom_end_time'] != null
        ? _formatTime(sched!['custom_end_time'])
        : (shift != null ? _formatTime(shift['end_time']) : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 40,
              color: isOff ? gray50 : schedColor.withOpacity(0.12),
              child: profileUrl.isNotEmpty
                  ? Image.network(
                      profileUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(initials,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isOff ? gray400 : schedColor)),
                      ),
                    )
                  : Center(
                      child: Text(initials,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isOff ? gray400 : schedColor)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF1a2a3a))),
                    if (isOverride) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: amber50, borderRadius: BorderRadius.circular(4)),
                        child: const Text('override',
                            style: TextStyle(
                                fontSize: 9,
                                color: amber400,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                if (isOff)
                  const Text('วันหยุด', style: TextStyle(fontSize: 11, color: gray400))
                else
                  Row(
                    children: [
                      if (shift != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: schedColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(shift['name'],
                              style: TextStyle(
                                  fontSize: 10,
                                  color: schedColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (startStr != null)
                        Text('$startStr – ${endStr ?? '--:--'}',
                            style: const TextStyle(fontSize: 11, color: gray400)),
                    ],
                  ),
              ],
            ),
          ),
          if (widget.showOverrideButton)
            GestureDetector(
              onTap: () {
                final existingOv = _overrides.cast<Map?>().firstWhere(
                  (o) =>
                      o!['employee_id'].toString() == emp['id'].toString() &&
                      o['override_date'].toString() == _toDateStr(date),
                  orElse: () => null,
                );
                _openOverrideForm(existing: existingOv, employee: emp);
              },
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isOverride ? amber50 : blue50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isOverride ? Icons.edit_rounded : Icons.edit_calendar_rounded,
                  size: 15,
                  color: isOverride ? amber400 : blue600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // TAB 2 — OVERRIDE LIST
  // ════════════════════════════════════════════

  Widget _buildOverrideTab() {
    final grouped = <String, List>{};
    for (final o in _overrides) {
      final d = o['override_date'].toString();
      grouped.putIfAbsent(d, () => []).add(o);
    }
    final sortedDates = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: blue600,
      child: sortedDates.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration:
                        const BoxDecoration(color: amber50, shape: BoxShape.circle),
                    child: const Icon(Icons.edit_calendar_rounded,
                        size: 48, color: amber400),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ไม่มี Override ใน${_thaiMonths[_focusedMonth.month - 1]}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: blue800),
                  ),
                  const SizedBox(height: 6),
                  const Text('กด "เพิ่ม Override" เพื่อเพิ่มงานพิเศษ',
                      style: TextStyle(fontSize: 12, color: gray400)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: sortedDates.length,
              itemBuilder: (_, i) {
                final dateStr = sortedDates[i];
                final items = grouped[dateStr]!;
                final dt = DateTime.parse(dateStr);
                final isToday = DateTime.now().year == dt.year &&
                    DateTime.now().month == dt.month &&
                    DateTime.now().day == dt.day;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isToday ? blue600 : blue50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_dayShort[dt.weekday % 7]} ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year + 543}${isToday ? '  (วันนี้)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isToday ? Colors.white : blue800,
                        ),
                      ),
                    ),
                    ...items.map((ov) => _buildOverrideCard(ov)),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildOverrideCard(Map ov) {
    final typeColors = {
      'special': [blue600, blue50],
      'ot': [amber400, amber50],
      'leave': [red400, red50],
      'substitute': [teal400, teal50],
    };
    final typeLabels = {
      'special': 'งานพิเศษ',
      'ot': 'OT',
      'leave': 'ลา/หยุด',
      'substitute': 'แทนคน',
    };
    final typeIcons = {
      'special': Icons.star_rounded,
      'ot': Icons.more_time_rounded,
      'leave': Icons.beach_access_rounded,
      'substitute': Icons.swap_horiz_rounded,
    };

    final ovType = ov['override_type'] ?? 'special';
    final colors = typeColors[ovType] ?? [blue600, blue50];
    final c = colors[0] as Color;
    final bg = colors[1] as Color;
    final shift = ov['shift_templates'];
    final empName = ov['employees']?['full_name'] ?? '-';
    final siteName = ov['work_sites']?['name'];
    final note = ov['note'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(13)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(typeIcons[ovType] ?? Icons.event_rounded, size: 18, color: c),
                const SizedBox(height: 4),
                Text(typeLabels[ovType] ?? ovType,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9, color: c, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(empName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF1a2a3a))),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (shift != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: () {
                              final h = (shift['color'] ?? '#185FA5')
                                  .replaceAll('#', '');
                              return Color(int.parse('FF$h', radix: 16))
                                  .withOpacity(0.1);
                            }(),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(shift['name'],
                              style: TextStyle(
                                  fontSize: 10,
                                  color: () {
                                    final h = (shift['color'] ?? '#185FA5')
                                        .replaceAll('#', '');
                                    return Color(int.parse('FF$h', radix: 16));
                                  }(),
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (ov['custom_start_time'] != null)
                        Text(
                          '${_formatTime(ov['custom_start_time'])} – ${_formatTime(ov['custom_end_time'])}',
                          style: const TextStyle(fontSize: 11, color: gray400),
                        )
                      else if (shift != null)
                        Text(
                          '${_formatTime(shift['start_time'])} – ${_formatTime(shift['end_time'])}',
                          style: const TextStyle(fontSize: 11, color: gray400),
                        ),
                    ],
                  ),
                  if (siteName != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 10, color: teal400),
                        const SizedBox(width: 2),
                        Text(siteName,
                            style:
                                const TextStyle(fontSize: 10, color: teal400)),
                      ],
                    ),
                  ],
                  if (note != null && note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('📝 $note',
                        style: const TextStyle(fontSize: 10, color: gray400)),
                  ],
                ],
              ),
            ),
          ),
          if (widget.showOverrideButton)
            GestureDetector(
              onTap: () => _openOverrideForm(existing: ov),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: amber50, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.edit_rounded, size: 15, color: amber400),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════════

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  Widget _legendDot(Color color, String label) => Row(
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: gray400)),
        ],
      );

  Widget _buildSectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold, color: blue800));

  Widget _chip({
    required String label,
    String? sublabel,
    required bool selected,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? bg : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? color : blue100, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? color : gray400)),
              if (sublabel != null)
                Text(sublabel,
                    style: TextStyle(
                        fontSize: 10,
                        color: selected ? color.withOpacity(0.7) : gray400)),
            ],
          ),
        ),
      );

  Widget _timeTile({
    required TimeOfDay time,
    required Color color,
    required Color bg,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12, color: gray400, fontWeight: FontWeight.w500));

  // ════════════════════════════════════════════
  // UTILS
  // ════════════════════════════════════════════

  String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      double _responsiveFontSize(BuildContext context, {
  required double mobile,
  required double desktop,
}) {
  final width = MediaQuery.of(context).size.width;
  return width < 600 ? mobile : desktop;
}

  String _toTimeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  TimeOfDay _parseTime(String t) {
    final p = t.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _formatTime(String? t) {
    if (t == null) return '--:--';
    final p = t.split(':');
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? red400 : teal400,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ════════════════════════════════════════════
  // SHIFT ASSIGNER — โหลด effective schedule (override + weekly)
  // ════════════════════════════════════════════

  void _openShiftAssigner(DateTime date) {
    final Map<String, String?> shiftAssignments = {};
    final Map<String, String?> shiftSiteAssignments = {};
    final Map<String, String?> originalAssignments = {}; // Track original assignments
    final dayOfWeek = date.weekday % 7;

    for (final shift in _shifts) {
      final shiftId = shift['id'].toString();

      // 1. หา override ตรงๆ ก่อน
      final existingOv = (_overrides as List).cast<Map?>().firstWhere(
            (o) =>
                o!['override_date'].toString() == _toDateStr(date) &&
                o['shift_template_id']?.toString() == shiftId,
            orElse: () => null,
          );

      if (existingOv != null) {
        // มี override → ใช้ค่าจาก override
        shiftAssignments[shiftId] = existingOv['employee_id']?.toString();
        shiftSiteAssignments[shiftId] = existingOv['work_site_id']?.toString();
      } else {
        // 2. ไม่มี override → หาจาก weekly schedule ว่าใครทำกะนี้วันนี้
        String? empIdFromWeekly;
        String? siteIdFromWeekly;
        for (final emp in _employees) {
          final empId = emp['id'].toString();
          final wk = _weeklyMap[empId]?[dayOfWeek];
          if (wk?['shift_template_id']?.toString() == shiftId) {
            empIdFromWeekly = empId;
            // weekly schedule ไม่มี work_site_id ตรงๆ ใช้ของ employee แทน
            siteIdFromWeekly = emp['work_site_id']?.toString();
            break;
          }
        }
        shiftAssignments[shiftId] = empIdFromWeekly;
        shiftSiteAssignments[shiftId] = siteIdFromWeekly;
      }
      
      // Store original assignment
      originalAssignments[shiftId] = shiftAssignments[shiftId];
    }

    final dateLabel =
        '${_dayShort[date.weekday % 7]} ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year + 543}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: gray400),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [blue800, blue600]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.swap_horiz_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('จัดกะวันนี้',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: blue800)),
                          Text(dateLabel,
                              style: const TextStyle(
                                  fontSize: 12, color: gray400)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_shifts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: amber50,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: amber400, size: 16),
                          SizedBox(width: 8),
                          Text('ยังไม่มีกะ กรุณาเพิ่มกะก่อน',
                              style: TextStyle(color: amber400, fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    ..._shifts.map((shift) {
                      final shiftId = shift['id'].toString();
                      var hex = shift['color'] ?? '#185FA5';
                      final h = hex.replaceAll('#', '');
                      final shiftColor = Color(int.parse('FF$h', radix: 16));
                      final startStr = _formatTime(shift['start_time']);
                      final endStr = _formatTime(shift['end_time']);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: shiftColor.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: shiftColor.withOpacity(0.1),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(13)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: shiftColor,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(shift['name'] ?? '-',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: shiftColor)),
                                  const Spacer(),
                                  Text('$startStr – $endStr',
                                      style: TextStyle(
                                          fontSize: 11, color: shiftColor)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                              child: Text('พนักงาน',
                                  style: TextStyle(
                                      fontSize: 11, color: gray400)),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                decoration: BoxDecoration(
                                  color: blue50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: blue100),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: shiftAssignments[shiftId],
                                    isExpanded: true,
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(
                                        color: Color(0xFF1a2a3a), fontSize: 13),
                                    hint: const Text('— ไม่มีคนทำกะนี้ —',
                                        style: TextStyle(
                                            color: gray400, fontSize: 13)),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('— ไม่มีคนทำกะนี้ —',
                                            style:
                                                TextStyle(color: gray400)),
                                      ),
                                      ..._filteredEmployees.map((emp) {
                                        final name = emp['full_name'] ?? '-';
                                        return DropdownMenuItem<String>(
                                          value: emp['id'].toString(),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  color: shiftColor
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    name.length >= 2
                                                        ? name.substring(0, 2)
                                                        : name,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: shiftColor),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(name),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (v) => setModal(
                                        () => shiftAssignments[shiftId] = v),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 14, 4),
                              child: Text('สาขา / บริษัท',
                                  style: TextStyle(
                                      fontSize: 11, color: gray400)),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                decoration: BoxDecoration(
                                  color: blue50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: blue100),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: shiftSiteAssignments[shiftId],
                                    isExpanded: true,
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(
                                        color: Color(0xFF1a2a3a), fontSize: 13),
                                    hint: const Text('ใช้ค่าปัจจุบัน',
                                        style: TextStyle(
                                            color: gray400, fontSize: 12)),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('ใช้ค่าปัจจุบัน',
                                            style:
                                                TextStyle(color: gray400)),
                                      ),
                                      ..._workSites.map(
                                          (s) => DropdownMenuItem<String>(
                                                value: s['id'].toString(),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                        Icons
                                                            .location_on_rounded,
                                                        size: 14,
                                                        color: teal400),
                                                    const SizedBox(width: 6),
                                                    Text(s['name'] ?? '-'),
                                                  ],
                                                ),
                                              )),
                                    ],
                                    onChanged: (v) => setModal(() =>
                                        shiftSiteAssignments[shiftId] = v),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmShiftChanges(
                        ctx: ctx,
                        date: date,
                        newAssignments: shiftAssignments,
                        originalAssignments: originalAssignments,
                        shiftSiteAssignments: shiftSiteAssignments,
                      ),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('บันทึกกะวันนี้',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WeeklyScheduleUI extends StatefulWidget {
  final Map employee;
  const WeeklyScheduleUI({super.key, required this.employee});

  @override
  State<WeeklyScheduleUI> createState() => _WeeklyScheduleUIState();
}

class _WeeklyScheduleUIState extends State<WeeklyScheduleUI> {
  final supabase = Supabase.instance.client;

  List _shifts = [];
  List _workSites = [];
  Map<int, Map?> _weeklyMap = {};
  bool _isLoading = true;

  // ── palette ──────────────────────────────────────────────
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

  static const List<String> _dayNames = [
    'อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ',
    'พฤหัส', 'ศุกร์', 'เสาร์',
  ];
  static const List<String> _dayShort = [
    'อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส',
  ];

  // preset groups for quick bulk select
  static const List<Map<String, dynamic>> _presets = [
    {'label': 'จ–ศ', 'days': [1, 2, 3, 4, 5]},
    {'label': 'จ–เส', 'days': [1, 2, 3, 4, 5, 6]},
    {'label': 'เสาร์–อา', 'days': [6, 0]},
    {'label': 'ทุกวัน', 'days': [0, 1, 2, 3, 4, 5, 6]},
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }
  Future<void> _applyPatternToMonth({
  required int year,
  required int month,
  bool skipExisting = false,
}) async {
  if (_weeklyMap.isEmpty) {
    _snack('ยังไม่มี pattern รายสัปดาห์ กรุณาตั้งตารางก่อน', isError: true);
    return;
  }

  final empId = widget.employee['id'].toString();
  final daysInMonth = DateTime(year, month + 1, 0).day;

  // สร้าง list ของ payload ทุกวันที่ match pattern
  final List<Map<String, dynamic>> payloads = [];
  for (int day = 1; day <= daysInMonth; day++) {
    final date = DateTime(year, month, day);
    final dow = date.weekday % 7; // 0=อา, 1=จ, ..., 6=ส

    final sched = _weeklyMap[dow]; // null = วันหยุด
    if (sched == null) continue;   // ข้ามวันหยุด

    final dateStr =
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    payloads.add({
      'employee_id':       empId,
      'override_date':     dateStr,
      'shift_template_id': sched['shift_template_id'],
      'work_site_id':      sched['work_site_id'],
      'override_type':     'special',
      'custom_start_time': sched['custom_start_time'],
      'custom_end_time':   sched['custom_end_time'],
      'note':              'Auto from weekly pattern',
    });
  }

  if (payloads.isEmpty) {
    _snack('ไม่มีวันทำงานใน pattern', isError: true);
    return;
  }

  try {
    // ถ้าต้องการไม่ทับรายการที่มีอยู่ ให้กรอง payloads โดยเช็คกับตาราง overrides
    if (skipExisting) {
      final firstDay = '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay = '$year-${month.toString().padLeft(2, '0')}-${daysInMonth.toString().padLeft(2, '0')}';
      final existing = await supabase
          .from('schedule_overrides')
          .select('override_date')
          .eq('employee_id', empId)
          .gte('override_date', firstDay)
          .lte('override_date', lastDay);
      final existingDates = (existing as List).map((e) => e['override_date'].toString()).toSet();
      payloads.removeWhere((p) => existingDates.contains(p['override_date'] as String));
      if (payloads.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          _snack('ไม่มีวันใหม่ที่จะสร้าง (ทั้งหมดมี override อยู่แล้ว)');
        }
        return;
      }
    }

    // upsert ทีละ batch (Supabase รับ list ได้เลย)
    await supabase.from('schedule_overrides').upsert(
      payloads,
      onConflict: 'employee_id,override_date',
    );
    if (mounted) {
      Navigator.pop(context); // ปิด confirm dialog
      _snack('✅ สร้างตาราง ${payloads.length} วัน สำเร็จ');
    }
  } catch (e) {
    _snack('Error: $e', isError: true);
  }
}

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final shifts = await supabase
          .from('shift_templates')
          .select('*')
          .eq('is_active', true)
          .order('start_time');
      final sites = await supabase.from('work_sites').select().order('name');
      final weekly = await supabase
          .from('employee_weekly_schedules')
          .select('*, shift_templates(*), work_sites(name)')
          .eq('employee_id', widget.employee['id'].toString())
          .isFilter('effective_until', null)
          .order('day_of_week');

      final map = <int, Map?>{};
      for (final row in (weekly as List)) {
        map[row['day_of_week'] as int] = row;
      }

      if (mounted) {
        setState(() {
          _shifts    = shifts;
          _workSites = sites;
          _weeklyMap = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('โหลดข้อมูลล้มเหลว: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════
  // SAVE — upsert 1 วัน
  // ════════════════════════════════════════════
  Future<void> _saveDay({
    required int dayOfWeek,
    required String? shiftId,
    required String? siteId,
    required TimeOfDay? customStart,
    required TimeOfDay? customEnd,
  }) async {
    final empId = widget.employee['id'].toString();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    try {
      if (shiftId == null && customStart == null) {
        await supabase
            .from('employee_weekly_schedules')
            .delete()
            .eq('employee_id', empId)
            .eq('day_of_week', dayOfWeek);
        setState(() => _weeklyMap.remove(dayOfWeek));
      } else {
        final payload = {
          'employee_id':       empId,
          'day_of_week':       dayOfWeek,
          'shift_template_id': shiftId,
          'work_site_id':      siteId,
          'custom_start_time': customStart != null ? _toTimeStr(customStart) : null,
          'custom_end_time':   customEnd   != null ? _toTimeStr(customEnd)   : null,
          'effective_from':    today,
          'effective_until':   null,
        };
        await supabase.from('employee_weekly_schedules').upsert(
          payload,
          onConflict: 'employee_id,day_of_week,effective_from',
        );
      }
      await _loadAll();
      if (mounted) {
        Navigator.pop(context);
        _snack('✅ บันทึกตารางวัน${_dayNames[dayOfWeek]}แล้ว');
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════
  // SAVE BULK — upsert หลายวันพร้อมกัน
  // ════════════════════════════════════════════
  Future<void> _saveBulk({
    required List<int> days,
    required String? shiftId,
    required String? siteId,
    required TimeOfDay? customStart,
    required TimeOfDay? customEnd,
    required bool isOff,
  }) async {
    final empId = widget.employee['id'].toString();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    try {
      for (final day in days) {
        if (isOff) {
          await supabase
              .from('employee_weekly_schedules')
              .delete()
              .eq('employee_id', empId)
              .eq('day_of_week', day);
        } else {
          final payload = {
            'employee_id':       empId,
            'day_of_week':       day,
            'shift_template_id': shiftId,
            'work_site_id':      siteId,
            'custom_start_time': customStart != null ? _toTimeStr(customStart) : null,
            'custom_end_time':   customEnd   != null ? _toTimeStr(customEnd)   : null,
            'effective_from':    today,
            'effective_until':   null,
          };
          await supabase.from('employee_weekly_schedules').upsert(
            payload,
            onConflict: 'employee_id,day_of_week,effective_from',
          );
        }
      }
      await _loadAll();
      if (mounted) {
        Navigator.pop(context);
        final dayLabels = days.map((d) => _dayShort[d]).join(', ');
        _snack('✅ บันทึก $dayLabels แล้ว');
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }
   String _getImageUrl(String? val) {
    if (val == null || val.isEmpty) return '';
    if (val.startsWith('http')) return val;
    return supabase.storage.from('attendance').getPublicUrl(val);
  }

  // ════════════════════════════════════════════
  // BULK BOTTOM SHEET
  // ════════════════════════════════════════════
  void _openBulkEditor() {
    Set<int> selectedDays = {1, 2, 3, 4, 5}; // default จ-ศ
    String? selectedShiftId;
    String? selectedSiteId;
    bool useCustomTime = false;
    TimeOfDay customStart = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay customEnd   = const TimeOfDay(hour: 18, minute: 0);
    bool isOff = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Padding(
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
                    // handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: blue100, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),

                    // header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [blue800, blue600]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.date_range_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ตั้งหลายวันพร้อมกัน',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: blue800)),
                            Text(widget.employee['full_name'] ?? '-',
                                style: const TextStyle(fontSize: 12, color: gray400)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Presets ──
                    _label('เลือกด่วน'),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _presets.map((p) {
                          final presetDays = Set<int>.from(p['days'] as List);
                          final isActive = selectedDays.containsAll(presetDays) &&
                              presetDays.containsAll(selectedDays);
                          return GestureDetector(
                            onTap: () => setModal(() {
                              selectedDays = Set<int>.from(p['days'] as List);
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isActive ? blue600 : blue50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(p['label'] as String,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isActive ? Colors.white : blue600)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Day picker ──
                    _label('เลือกวัน (แตะเพื่อเลือก/ยกเลิก)'),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(7, (i) {
                        final isSelected = selectedDays.contains(i);
                        final hasExisting = _weeklyMap.containsKey(i);
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setModal(() {
                              if (isSelected) {
                                selectedDays.remove(i);
                              } else {
                                selectedDays.add(i);
                              }
                            }),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? blue600 : (hasExisting ? blue50 : Colors.white),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? blue600 : (hasExisting ? blue400 : blue100),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(_dayShort[i],
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : hasExisting
                                                  ? blue600
                                                  : gray400)),
                                  if (hasExisting && !isSelected) ...[
                                    const SizedBox(height: 3),
                                    Container(
                                      width: 4, height: 4,
                                      decoration: const BoxDecoration(
                                          color: blue400, shape: BoxShape.circle),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (selectedDays.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _infoBox('กรุณาเลือกอย่างน้อย 1 วัน', amber400, amber50),
                      ),
                    const SizedBox(height: 16),

                    // ── Work / Off toggle ──
                    Row(
                      children: [
                        _toggleChip(
                          label: 'ทำงาน',
                          icon: Icons.work_rounded,
                          active: !isOff,
                          activeColor: teal400,
                          activeBg: teal50,
                          onTap: () => setModal(() => isOff = false),
                        ),
                        const SizedBox(width: 10),
                        _toggleChip(
                          label: 'วันหยุด',
                          icon: Icons.beach_access_rounded,
                          active: isOff,
                          activeColor: red400,
                          activeBg: red50,
                          onTap: () => setModal(() => isOff = true),
                        ),
                      ],
                    ),

                    if (!isOff) ...[
                      const SizedBox(height: 16),

                      // ── Shift chips ──
                      _label('กะงาน'),
                      const SizedBox(height: 8),
                      _shifts.isEmpty
                          ? _infoBox('ยังไม่มีกะ กรุณาเพิ่มใน "จัดการกะงาน" ก่อน',
                              amber400, amber50)
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _shiftChip(
                                  label: 'กำหนดเอง',
                                  color: gray400,
                                  bg: gray50,
                                  selected: selectedShiftId == null,
                                  onTap: () =>
                                      setModal(() => selectedShiftId = null),
                                ),
                                ..._shifts.map((s) {
                                  final c = _hexToColor(s['color'] ?? '#185FA5');
                                  return _shiftChip(
                                    label: s['name'],
                                    sublabel:
                                        '${_formatTime(s['start_time'])} – ${_formatTime(s['end_time'])}',
                                    color: c,
                                    bg: c.withOpacity(0.1),
                                    selected: selectedShiftId == s['id'].toString(),
                                    onTap: () {
                                      setModal(() {
                                        selectedShiftId = s['id'].toString();
                                        customStart = _parseTime(s['start_time'] ?? '09:00');
                                        customEnd   = _parseTime(s['end_time']   ?? '18:00');
                                      });
                                    },
                                  );
                                }),
                              ],
                            ),
                      const SizedBox(height: 14),

                      // ── Custom time toggle ──
                      GestureDetector(
                        onTap: () =>
                            setModal(() => useCustomTime = !useCustomTime),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: useCustomTime ? blue50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: useCustomTime ? blue600 : blue100),
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
                              Text('กำหนดเวลาเฉพาะพนักงานคนนี้',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: useCustomTime ? blue800 : gray400,
                                      fontWeight: useCustomTime
                                          ? FontWeight.w600
                                          : FontWeight.normal)),
                              const Spacer(),
                              if (useCustomTime)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: blue600,
                                      borderRadius: BorderRadius.circular(4)),
                                  child: const Text('override',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ),
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
                                  _label('เวลาเริ่ม'),
                                  const SizedBox(height: 6),
                                  _timeTile(
                                    time: customStart,
                                    color: teal400,
                                    bg: teal50,
                                    icon: Icons.login_rounded,
                                    onTap: () async {
                                      final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: customStart);
                                      if (t != null)
                                        setModal(() => customStart = t);
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
                                  _label('เวลาเลิก'),
                                  const SizedBox(height: 6),
                                  _timeTile(
                                    time: customEnd,
                                    color: red400,
                                    bg: red50,
                                    icon: Icons.logout_rounded,
                                    onTap: () async {
                                      final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: customEnd);
                                      if (t != null)
                                        setModal(() => customEnd = t);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],


                      const SizedBox(height: 14),

                      // ── Site ──
                      _label('สาขา/บริษัท'),
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
                            style: const TextStyle(
                                color: Color(0xFF1a2a3a), fontSize: 13),
                            hint: const Text('ใช้ค่าปัจจุบันของพนักงาน',
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
                            onChanged: (v) =>
                                setModal(() => selectedSiteId = v),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 22),

                    // ── Save button ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: selectedDays.isEmpty
                            ? null
                            : () => _saveBulk(
                                  days: selectedDays.toList(),
                                  shiftId: isOff ? null : selectedShiftId,
                                  siteId: isOff ? null : selectedSiteId,
                                  customStart: (!isOff && useCustomTime)
                                      ? customStart
                                      : null,
                                  customEnd: (!isOff && useCustomTime)
                                      ? customEnd
                                      : null,
                                  isOff: isOff,
                                ),
                        icon: Icon(
                            isOff
                                ? Icons.beach_access_rounded
                                : Icons.save_rounded,
                            size: 16),
                        label: Text(
                          isOff
                              ? 'ตั้ง ${selectedDays.length} วัน เป็นวันหยุด'
                              : 'บันทึก ${selectedDays.length} วัน',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isOff ? red400 : blue600,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: gray50,
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
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════
  // SINGLE DAY BOTTOM SHEET
  // ════════════════════════════════════════════
  void _openDayEditor(int dayOfWeek) {
    final existing = _weeklyMap[dayOfWeek];

    String? selectedShiftId = existing?['shift_template_id']?.toString();
    String? selectedSiteId  = existing?['work_site_id']?.toString();
    bool    useCustomTime   = existing?['custom_start_time'] != null;
    TimeOfDay customStart   = _parseTime(existing?['custom_start_time'] ?? '09:00');
    TimeOfDay customEnd     = _parseTime(existing?['custom_end_time']   ?? '18:00');
    bool isOff = existing == null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: bgColor,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: blue100,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                    ),

                    // header
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [blue800, blue600]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              _dayShort[dayOfWeek],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('วัน${_dayNames[dayOfWeek]}',
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: blue800)),
                            Text(widget.employee['full_name'] ?? '-',
                                style: const TextStyle(
                                    fontSize: 12, color: gray400)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // toggle
                    Row(
                      children: [
                        _toggleChip(
                          label: 'ทำงาน',
                          icon: Icons.work_rounded,
                          active: !isOff,
                          activeColor: teal400,
                          activeBg: teal50,
                          onTap: () => setModal(() => isOff = false),
                        ),
                        const SizedBox(width: 10),
                        _toggleChip(
                          label: 'วันหยุด',
                          icon: Icons.beach_access_rounded,
                          active: isOff,
                          activeColor: red400,
                          activeBg: red50,
                          onTap: () => setModal(() => isOff = true),
                        ),
                      ],
                    ),

                    if (!isOff) ...[
                      const SizedBox(height: 18),
                      _label('กะงาน'),
                      const SizedBox(height: 8),
                      _shifts.isEmpty
                          ? _infoBox('ยังไม่มีกะ กรุณาเพิ่มใน "จัดการกะงาน" ก่อน',
                              amber400, amber50)
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _shiftChip(
                                  label: 'กำหนดเอง',
                                  color: gray400,
                                  bg: gray50,
                                  selected: selectedShiftId == null,
                                  onTap: () => setModal(
                                      () => selectedShiftId = null),
                                ),
                                ..._shifts.map((s) {
                                  final c =
                                      _hexToColor(s['color'] ?? '#185FA5');
                                  return _shiftChip(
                                    label: s['name'],
                                    sublabel:
                                        '${_formatTime(s['start_time'])} – ${_formatTime(s['end_time'])}',
                                    color: c,
                                    bg: c.withOpacity(0.1),
                                    selected: selectedShiftId ==
                                        s['id'].toString(),
                                    onTap: () {
                                      setModal(() {
                                        selectedShiftId =
                                            s['id'].toString();
                                        customStart = _parseTime(
                                            s['start_time'] ?? '09:00');
                                        customEnd = _parseTime(
                                            s['end_time'] ?? '18:00');
                                      });
                                    },
                                  );
                                }),
                              ],
                            ),
                      const SizedBox(height: 16),

                      GestureDetector(
                        onTap: () =>
                            setModal(() => useCustomTime = !useCustomTime),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: useCustomTime ? blue50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: useCustomTime ? blue600 : blue100),
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
                              Text('กำหนดเวลาเฉพาะพนักงานคนนี้',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: useCustomTime ? blue800 : gray400,
                                    fontWeight: useCustomTime
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  )),
                              const Spacer(),
                              if (useCustomTime)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: blue600,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('override',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        ),
                      ),

                      if (useCustomTime) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('เวลาเริ่ม'),
                                  const SizedBox(height: 6),
                                  _timeTile(
                                    time: customStart,
                                    color: teal400,
                                    bg: teal50,
                                    icon: Icons.login_rounded,
                                    onTap: () async {
                                      final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: customStart);
                                      if (t != null)
                                        setModal(() => customStart = t);
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
                                  _label('เวลาเลิก'),
                                  const SizedBox(height: 6),
                                  _timeTile(
                                    time: customEnd,
                                    color: red400,
                                    bg: red50,
                                    icon: Icons.logout_rounded,
                                    onTap: () async {
                                      final t = await showTimePicker(
                                          context: ctx,
                                          initialTime: customEnd);
                                      if (t != null)
                                        setModal(() => customEnd = t);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 16),
                      _label('สาขา/บริษัท วันนี้'),
                      const SizedBox(height: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: blue50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: blue100),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: selectedSiteId,
                            dropdownColor: Colors.white,
                            style: const TextStyle(
                                color: Color(0xFF1a2a3a), fontSize: 13),
                            hint: const Text('ใช้ค่าปัจจุบันของพนักงาน',
                                style: TextStyle(color: gray400, fontSize: 12)),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                  value: null,
                                  child: Text('ใช้ค่าปัจจุบัน',
                                      style: TextStyle(color: gray400))),
                              ..._workSites.map((s) =>
                                  DropdownMenuItem<String>(
                                    value: s['id'].toString(),
                                    child: Text(s['name']),
                                  )),
                            ],
                            onChanged: (v) =>
                                setModal(() => selectedSiteId = v),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 22),

                    // buttons
                    Row(
                      children: [
                        if (existing != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _saveDay(
                                dayOfWeek: dayOfWeek,
                                shiftId: null,
                                siteId: null,
                                customStart: null,
                                customEnd: null,
                              ),
                              icon: const Icon(Icons.delete_outline,
                                  size: 14, color: red400),
                              label: const Text('ลบออก',
                                  style: TextStyle(
                                      color: red400, fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: red400),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        if (existing != null) const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: isOff
                                ? () => _saveDay(
                                      dayOfWeek: dayOfWeek,
                                      shiftId: null,
                                      siteId: null,
                                      customStart: null,
                                      customEnd: null,
                                    )
                                : () => _saveDay(
                                      dayOfWeek: dayOfWeek,
                                      shiftId: selectedShiftId,
                                      siteId: selectedSiteId,
                                      customStart:
                                          useCustomTime ? customStart : null,
                                      customEnd:
                                          useCustomTime ? customEnd : null,
                                    ),
                            icon: Icon(
                                isOff
                                    ? Icons.beach_access_rounded
                                    : Icons.save_rounded,
                                size: 16),
                            label: Text(
                              isOff ? 'ตั้งเป็นวันหยุด' : 'บันทึก',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isOff ? red400 : blue600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  void _showApplyToMonthDialog() {
  int selectedYear  = DateTime.now().year;
  int selectedMonth = DateTime.now().month;
  bool skipExisting = false;

  final thaiMonths = [
    'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน',
    'พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม',
    'กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
  ];

  // สรุป pattern ปัจจุบัน
  final workDayLabels = _weeklyMap.keys.toList()
    ..sort();
  final patternStr = workDayLabels
      .map((d) => _dayShort[d])
      .join(', ');

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: blue50, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.calendar_month_rounded, color: blue600, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('ใช้กับทั้งเดือน',
                style: TextStyle(fontSize: 16, color: blue800, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // แสดง pattern
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: teal50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: teal400.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.repeat_rounded, size: 16, color: teal400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pattern ปัจจุบัน',
                            style: TextStyle(fontSize: 11, color: teal400)),
                        Text(
                          patternStr.isEmpty ? 'ยังไม่มี' : patternStr,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1a2a3a)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text('เลือกเดือนที่ต้องการ',
                style: TextStyle(fontSize: 12, color: gray400, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),

            // Month selector
            Row(
              children: [
                // ปี
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: blue50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: blue100),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedYear,
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
                        items: [
                          DateTime.now().year - 1,
                          DateTime.now().year,
                          DateTime.now().year + 1,
                        ].map((y) => DropdownMenuItem(
                          value: y,
                          child: Text('$y'),
                        )).toList(),
                        onChanged: (v) => setD(() => selectedYear = v!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // เดือน
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: blue50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: blue100),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedMonth,
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
                        isExpanded: true,
                        items: List.generate(12, (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(thaiMonths[i]),
                        )),
                        onChanged: (v) => setD(() => selectedMonth = v!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // คำเตือน
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: amber50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: amber400.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: amber400),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'จะ upsert override ทุกวันทำงานในเดือนนั้น\nหากมีอยู่แล้วจะทับค่าเดิม',
                      style: TextStyle(fontSize: 11, color: amber400, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Option: skip existing overrides
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ไม่ทับรายการที่มีอยู่ (ข้ามวันที่มี override อยู่แล้ว)'),
              value: skipExisting,
              onChanged: (v) => setD(() => skipExisting = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: gray400)),
          ),
          ElevatedButton.icon(
            onPressed: () => _applyPatternToMonth(
              year: selectedYear,
              month: selectedMonth,
              skipExisting: skipExisting,
            ),
            icon: const Icon(Icons.rocket_launch_rounded, size: 14),
            label: const Text('ใช้เลย',
                style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: blue600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    ),
  );
}

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final name = widget.employee['full_name'] ?? '-';
    final initials = name.length >= 2 ? name.substring(0, 2) : name;
    final profileUrl = _getImageUrl(widget.employee['profile_photo'] as String?);
    

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: blue800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('ตารางงานประจำสัปดาห์',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: blue600))
          : RefreshIndicator(
              onRefresh: _loadAll,
              color: blue600,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _buildEmployeeHeader(name, initials, profileUrl),
                  const SizedBox(height: 14),

                  // ── Bulk assign button ──────────────────
                  GestureDetector(
                    onTap: _openBulkEditor,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [blue800, blue600],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.date_range_rounded,
                                color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ตั้งหลายวันพร้อมกัน',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Text('เช่น จ–ศ ทั้งหมด หรือเลือกเองได้เลย',
                                    style: TextStyle(
                                        color: blue100, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: Colors.white70, size: 14),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

        // ── Apply to month button ──────────────────
        GestureDetector(
          onTap: _showApplyToMonthDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: teal400.withOpacity(0.5), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: teal50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: teal400, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ใช้กับทั้งเดือน',
                          style: TextStyle(
                              color: blue800,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      Text('Generate ตารางทั้งเดือนจาก pattern นี้',
                          style: TextStyle(color: gray400, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
            color: teal400, size: 14),
      ],
    ),
  ),
),
                  const SizedBox(height: 14),

                  _buildWeekSummaryRow(),
                  const SizedBox(height: 14),
                  _buildWeekStatsRow(),
                  const SizedBox(height: 14),
                  _buildSectionTitle('ตารางรายวัน'),
                  const SizedBox(height: 10),
                  ...List.generate(7, (i) => _buildDayRow(i)),
                ],
              ),
            ),
    );
  }

  // ── Employee header ──────────────────────────────────────
  Widget _buildEmployeeHeader(
      String name, String initials, String profileUrl) {
    return Container(
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
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: profileUrl.isNotEmpty
                ? Image.network(profileUrl,
                    width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(initials))
                : _avatarFallback(initials),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(
                  widget.employee['department'] ?? '-',
                  style: const TextStyle(color: blue100, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_weeklyMap.length}/7 วัน',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const Text('ตารางปัจจุบัน',
                  style: TextStyle(color: blue100, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Week summary dots ────────────────────────────────────
  Widget _buildWeekSummaryRow() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      child: Row(
        children: List.generate(7, (i) {
          final hasSchedule = _weeklyMap.containsKey(i);
          final isToday = DateTime.now().weekday % 7 == i;
          final sched = _weeklyMap[i];
          final shiftColor = sched != null
              ? _hexToColor(
                  sched['shift_templates']?['color'] ?? '#185FA5')
              : gray400;

          return Expanded(
            child: GestureDetector(
              onTap: () => _openDayEditor(i),
              child: Column(
                children: [
                  Text(_dayShort[i],
                      style: TextStyle(
                          fontSize: 11,
                          color: isToday ? blue600 : gray400,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  const SizedBox(height: 6),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: hasSchedule
                          ? shiftColor.withOpacity(0.15)
                          : gray50,
                      shape: BoxShape.circle,
                      border: isToday
                          ? Border.all(color: blue600, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: hasSchedule
                          ? Icon(Icons.check_rounded,
                              size: 14, color: shiftColor)
                          : const Icon(Icons.remove_rounded,
                              size: 14, color: gray400),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Week stats (ทำงาน/หยุด/ชั่วโมง) ─────────────────────
  Widget _buildWeekStatsRow() {
    final workDays = _weeklyMap.length;
    final offDays = 7 - workDays;

    // คำนวณชั่วโมงรวม
    double totalHours = 0;
    for (final sched in _weeklyMap.values) {
      if (sched == null) continue;
      final shift = sched['shift_templates'];
      final startStr = sched['custom_start_time'] ?? shift?['start_time'];
      final endStr   = sched['custom_end_time']   ?? shift?['end_time'];
      if (startStr != null && endStr != null) {
        final s = _parseTime(startStr);
        final e = _parseTime(endStr);
        double hours = (e.hour * 60 + e.minute - s.hour * 60 - s.minute) / 60.0;
        if (hours < 0) hours += 24;
        totalHours += hours;
      }
    }

    return Row(
      children: [
        _statCard('$workDays', 'วันทำงาน', Icons.work_rounded, teal400, teal50),
        const SizedBox(width: 8),
        _statCard('$offDays', 'วันหยุด', Icons.beach_access_rounded, red400, red50),
        const SizedBox(width: 8),
        _statCard(
            totalHours > 0
                ? '${totalHours.toStringAsFixed(0)} ชม.'
                : '—',
            'รวม/สัปดาห์',
            Icons.schedule_rounded,
            amber400,
            amber50),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style: const TextStyle(fontSize: 9, color: gray400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Day row ──────────────────────────────────────────────
  Widget _buildDayRow(int dayOfWeek) {
    final sched = _weeklyMap[dayOfWeek];
    final isToday = DateTime.now().weekday % 7 == dayOfWeek;
    final hasSchedule = sched != null;

    final shift = sched?['shift_templates'];
    final shiftColor = shift != null
        ? _hexToColor(shift['color'] ?? '#185FA5')
        : gray400;

    final startStr = sched?['custom_start_time'] != null
        ? _formatTime(sched!['custom_start_time'])
        : (shift != null ? _formatTime(shift['start_time']) : null);
    final endStr = sched?['custom_end_time'] != null
        ? _formatTime(sched!['custom_end_time'])
        : (shift != null ? _formatTime(shift['end_time']) : null);
    final hasCustomTime = sched?['custom_start_time'] != null;
    final siteName = sched?['work_sites']?['name'];

    // คำนวณชั่วโมง
    String? hoursStr;
    if (startStr != null && endStr != null && startStr != '--:--') {
      final s = _parseTime(startStr.replaceAll(':', ':'));
      final e = _parseTime(endStr.replaceAll(':', ':'));
      double h = (e.hour * 60 + e.minute - s.hour * 60 - s.minute) / 60.0;
      if (h < 0) h += 24;
      hoursStr = '${h.toStringAsFixed(1)} ชม.';
    }

    return GestureDetector(
      onTap: () => _openDayEditor(dayOfWeek),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isToday ? blue600 : blue100,
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // day strip
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: isToday
                    ? blue600
                    : (hasSchedule
                        ? shiftColor.withOpacity(0.08)
                        : gray50),
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(13)),
              ),
              child: Column(
                children: [
                  Text(
                    _dayShort[dayOfWeek],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isToday
                          ? Colors.white
                          : hasSchedule
                              ? shiftColor
                              : gray400,
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 5, height: 5,
                      decoration: const BoxDecoration(
                          color: Colors.white70, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ),

            // content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: hasSchedule
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (shift != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: shiftColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    shift['name'] ?? '',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: shiftColor,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              if (hasCustomTime) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: blue600,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('custom',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                              const Spacer(),
                              if (hoursStr != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: amber50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(hoursStr,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: amber400,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.login_rounded,
                                  size: 13, color: teal400),
                              const SizedBox(width: 4),
                              Text(
                                startStr ?? '--:--',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1a2a3a)),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded,
                                  size: 12, color: gray400),
                              const SizedBox(width: 8),
                              const Icon(Icons.logout_rounded,
                                  size: 13, color: red400),
                              const SizedBox(width: 4),
                              Text(
                                endStr ?? '--:--',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1a2a3a)),
                              ),
                            ],
                          ),
                          if (siteName != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 11, color: teal400),
                                const SizedBox(width: 2),
                                Text(siteName,
                                    style: const TextStyle(
                                        fontSize: 10, color: teal400)),
                              ],
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: gray50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('วันหยุด / ไม่มีตาราง',
                                style:
                                    TextStyle(fontSize: 12, color: gray400)),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: blue50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_rounded,
                                color: blue600, size: 16),
                          ),
                        ],
                      ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right_rounded,
                  color: gray400, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════════
  Widget _buildSectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold, color: blue800));

  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required Color activeBg,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? activeBg : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? activeColor : blue100,
                width: active ? 1.5 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? activeColor : gray400),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active ? FontWeight.bold : FontWeight.normal,
                      color: active ? activeColor : gray400)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shiftChip({
    required String label,
    String? sublabel,
    required Color color,
    required Color bg,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? bg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : blue100,
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 12, color: color),
                if (selected) const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? color : gray400)),
              ],
            ),
            if (sublabel != null) ...[
              const SizedBox(height: 2),
              Text(sublabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: selected ? color.withOpacity(0.7) : gray400)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timeTile({
    required TimeOfDay time,
    required Color color,
    required Color bg,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
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
                  fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12, color: gray400, fontWeight: FontWeight.w500));

  Widget _infoBox(String text, Color color, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: color),
            const SizedBox(width: 6),
            Flexible(
                child: Text(text,
                    style: TextStyle(fontSize: 11, color: color))),
          ],
        ),
      );

  Widget _avatarFallback(String initials) => Container(
        width: 56, height: 56, color: blue50,
        child: Center(
          child: Text(initials,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: blue800,
                  fontSize: 18)),
        ),
      );

  // ════════════════════════════════════════════
  // UTILS
  // ════════════════════════════════════════════
  TimeOfDay _parseTime(String t) {
    final p = t.split(':');
    return TimeOfDay(
        hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _toTimeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _formatTime(String? t) {
    if (t == null) return '--:--';
    final p = t.split(':');
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? red400 : teal400,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}
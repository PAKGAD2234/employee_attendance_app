import 'package:employee_attendance_app/view/checkout_ui.dart';
import 'package:employee_attendance_app/view/employee_history_ui.dart';
import 'package:employee_attendance_app/view/employee_profile_ui.dart';
import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:employee_attendance_app/widgets/clock_widget.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'checkin_ui.dart';

class EmployeeHomeView extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String employeePhone;
  const EmployeeHomeView({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.employeePhone,
  });

  @override
  State<EmployeeHomeView> createState() => _EmployeeHomeViewState();
}

class _EmployeeHomeViewState extends State<EmployeeHomeView>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final supabaseService = SupabaseService();

  String fullName = '';
  String profilePhotoUrl = '';
  String status = 'ยังไม่ลงเวลา';
  bool isLoadingUser = true;

  Map<String, dynamic>? _todayShift;
  String _shiftSource = '';

  // ── calendar state ──
  DateTime _focusedMonth = DateTime.now();
  List _overrides = [];
  Map<int, Map> _weeklyMap = {}; // dayOfWeek -> schedule row
  bool _calendarLoading = true;
  bool _calendarExpanded = false;

  static const List<String> _dayShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];
  static const List<String> _thaiMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.',
    'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.',
    'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    supabaseService.initialize(supabase);
    loadUser();
    _loadCalendar();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> loadUser() async {
    final data = await supabaseService.getEmployee(widget.employeeId);

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final todayRecord = await supabase
        .from('attendance')
        .select('checkin_time, checkout_time')
        .eq('employee_id', widget.employeeId)
        .eq('work_date', today)
        .maybeSingle();

    final dayOfWeek = now.weekday % 7;

    final override = await supabase
        .from('schedule_overrides')
        .select('*, shift_templates(*), work_sites(name)')
        .eq('employee_id', widget.employeeId)
        .eq('override_date', today)
        .maybeSingle();

    Map<String, dynamic>? todayShift;
    String shiftSource = '';

    if (override != null) {
      todayShift = override;
      shiftSource = 'override';
    } else {
      final weekly = await supabase
          .from('employee_weekly_schedules')
          .select('*, shift_templates(*), work_sites(name)')
          .eq('employee_id', widget.employeeId)
          .eq('day_of_week', dayOfWeek)
          .isFilter('effective_until', null)
          .maybeSingle();
      if (weekly != null) {
        todayShift = weekly;
        shiftSource = 'weekly';
      }
    }

    if (!mounted) return;
    setState(() {
      fullName = data?['full_name'] ?? 'Unknown';
      profilePhotoUrl =
          supabaseService.getProfilePhotoUrl(data?['profile_photo']);
      isLoadingUser = false;

      if (todayRecord == null) {
        status = 'ยังไม่ลงเวลา';
      } else if (todayRecord['checkout_time'] != null) {
        status = 'ออกงานแล้ว';
      } else {
        status = 'เข้างานแล้ว';
      }

      _todayShift = todayShift;
      _shiftSource = shiftSource;
    });
  }

  Future<void> _loadCalendar() async {
    setState(() => _calendarLoading = true);
    try {
      final year = _focusedMonth.year;
      final month = _focusedMonth.month;
      final firstDay =
          '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay =
          '$year-${month.toString().padLeft(2, '0')}-${DateTime(year, month + 1, 0).day.toString().padLeft(2, '0')}';

      final overrides = await supabase
          .from('schedule_overrides')
          .select('*, shift_templates(*)')
          .eq('employee_id', widget.employeeId)
          .gte('override_date', firstDay)
          .lte('override_date', lastDay);

      final weeklies = await supabase
          .from('employee_weekly_schedules')
          .select('*, shift_templates(*)')
          .eq('employee_id', widget.employeeId)
          .isFilter('effective_until', null);

      final wMap = <int, Map>{};
      for (final row in (weeklies as List)) {
        wMap[row['day_of_week'] as int] = row;
      }

      if (!mounted) return;
      setState(() {
        _overrides = overrides;
        _weeklyMap = wMap;
        _calendarLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  Map? _getEffective(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final dayOfWeek = date.weekday % 7;

    final ov = (_overrides as List).cast<Map?>().firstWhere(
          (o) => o!['override_date'].toString() == dateStr,
          orElse: () => null,
        );
    if (ov != null) return {...ov, '_source': 'override'};

    final wk = _weeklyMap[dayOfWeek];
    if (wk != null) return {...wk, '_source': 'weekly'};

    return null;
  }

  Color _shiftColor(Map? sched) {
    if (sched == null) return Colors.transparent;
    if (sched['override_type'] == 'leave') return const Color(0xFFE24B4A);
    final shift = sched['shift_templates'];
    if (shift == null) return const Color(0xFF29B6F6);
    final hex = (shift['color'] ?? '#29B6F6').replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color get _statusColor {
    if (status == 'เข้างานแล้ว') return Colors.green;
    if (status == 'ออกงานแล้ว') return const Color(0xFF29B6F6);
    return Colors.orange;
  }

  // ════════════════════════════════════════════
  // CALENDAR WIDGET
  // ════════════════════════════════════════════

  Widget _buildCalendar() {
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          // ── header month nav ──
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1));
                  _loadCalendar();
                },
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 18),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_thaiMonths[_focusedMonth.month - 1]} ${_focusedMonth.year + 543}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1));
                  _loadCalendar();
                },
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 18),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── day headers ──
          Row(
            children: _dayShort
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.40),
                            )),
                      ),
                    ))
                .toList(),
          ),

          const SizedBox(height: 6),

          // ── grid ──
          _calendarLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: Color(0xFF29B6F6), strokeWidth: 2),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: firstWeekday + daysInMonth,
                  itemBuilder: (_, idx) {
                    if (idx < firstWeekday) return const SizedBox();
                    final day = idx - firstWeekday + 1;
                    final date = DateTime(
                        _focusedMonth.year, _focusedMonth.month, day);
                    final isToday = today.year == date.year &&
                        today.month == date.month &&
                        today.day == date.day;

                    final sched = _getEffective(date);
                    final shift = sched?['shift_templates'];
                    final isLeave = sched?['override_type'] == 'leave';
                    final color = _shiftColor(sched);
                    final hasShift = sched != null;

                    String? startStr;
                    String? endStr;
                    if (!isLeave && hasShift) {
                      final st = sched!['custom_start_time'] ??
                          shift?['start_time'];
                      final et =
                          sched['custom_end_time'] ?? shift?['end_time'];
                      if (st != null)
                        startStr = st.toString().substring(0, 5);
                      if (et != null)
                        endStr = et.toString().substring(0, 5);
                    }

                    final shiftName = isLeave
                        ? 'ลา'
                        : (shift?['name'] ?? '');

                    return Container(
                      decoration: BoxDecoration(
                        color: isToday
                            ? const Color(0xFF29B6F6).withOpacity(0.20)
                            : hasShift
                                ? color.withOpacity(0.10)
                                : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isToday
                              ? const Color(0xFF29B6F6).withOpacity(0.70)
                              : hasShift
                                  ? color.withOpacity(0.30)
                                  : Colors.white.withOpacity(0.06),
                          width: isToday ? 1.5 : 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(3, 4, 3, 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // วันที่
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isToday
                                  ? const Color(0xFF29B6F6)
                                  : Colors.white.withOpacity(0.85),
                            ),
                          ),
                          if (hasShift) ...[
                            const SizedBox(height: 2),
                            // ชื่อกะ
                            Text(
                              shiftName,
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w600,
                                color: isLeave
                                    ? const Color(0xFFE24B4A)
                                    : color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            if (startStr != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                '$startStr',
                                style: TextStyle(
                                  fontSize: 7,
                                  color: Colors.white.withOpacity(0.45),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                '$endStr',
                                style: TextStyle(
                                  fontSize: 7,
                                  color: Colors.white.withOpacity(0.45),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
                ),

          // ── legend ──
          if (!_calendarLoading) ...[
            const SizedBox(height: 8),
            _buildLegend(),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final shifts = <String, Color>{};
    for (final row in _weeklyMap.values) {
      final shift = row['shift_templates'];
      if (shift != null) {
        final hex = (shift['color'] ?? '#29B6F6').replaceAll('#', '');
        shifts[shift['name'] ?? ''] =
            Color(int.parse('FF$hex', radix: 16));
      }
    }

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        ...shifts.entries.map((e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                      color: e.value, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(e.key,
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withOpacity(0.50))),
              ],
            )),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7, height: 7,
              decoration: const BoxDecoration(
                  color: Color(0xFFE24B4A), shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('ลา/หยุด',
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.50))),
          ],
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  // TODAY SHIFT CARD
  // ════════════════════════════════════════════

  Widget _buildTodayShiftCard() {
    final shift = _todayShift?['shift_templates'] as Map?;
    final ovType = _todayShift?['override_type'] as String?;
    final siteName = _todayShift?['work_sites']?['name'] as String?;
    final isLeave = ovType == 'leave';
    final isOverride = _shiftSource == 'override';
    final hasShift = _todayShift != null && !isLeave;

    String startTime = '--:--';
    String endTime = '--:--';
    if (_todayShift?['custom_start_time'] != null) {
      startTime =
          _todayShift!['custom_start_time'].toString().substring(0, 5);
    } else if (shift?['start_time'] != null) {
      startTime = shift!['start_time'].toString().substring(0, 5);
    }
    if (_todayShift?['custom_end_time'] != null) {
      endTime = _todayShift!['custom_end_time'].toString().substring(0, 5);
    } else if (shift?['end_time'] != null) {
      endTime = shift!['end_time'].toString().substring(0, 5);
    }

    Color shiftColor = const Color(0xFF29B6F6);
    if (isOverride && ovType != null) {
      shiftColor = {
            'special': const Color(0xFF378ADD),
            'ot': const Color(0xFFBA7517),
            'leave': const Color(0xFFE24B4A),
            'substitute': const Color(0xFF1D9E75),
          }[ovType] ??
          shiftColor;
    } else if (shift?['color'] != null) {
      final h = (shift!['color'] as String).replaceAll('#', '');
      shiftColor = Color(int.parse('FF$h', radix: 16));
    }

    final shiftName = isLeave
        ? 'วันหยุด / ลา'
        : (shift?['name'] ??
            (_todayShift != null ? 'กะพิเศษ' : 'ไม่มีตารางงาน'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'ตารางกะวันนี้',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.45),
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(hasShift ? 0.07 : 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasShift
                  ? shiftColor.withOpacity(0.25)
                  : Colors.white.withOpacity(0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: shiftColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: shiftColor.withOpacity(0.25)),
                ),
                child: Icon(
                  isLeave
                      ? Icons.beach_access_rounded
                      : hasShift
                          ? Icons.calendar_today_rounded
                          : Icons.event_busy_rounded,
                  size: 18,
                  color: hasShift
                      ? shiftColor
                      : Colors.white.withOpacity(0.30),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shiftName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasShift
                            ? Colors.white
                            : Colors.white.withOpacity(0.40),
                      ),
                    ),
                    if (hasShift) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 11,
                              color: Colors.white.withOpacity(0.45)),
                          const SizedBox(width: 3),
                          Text(
                            '$startTime – $endTime',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                      if (siteName != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 11,
                                color: shiftColor.withOpacity(0.75)),
                            const SizedBox(width: 3),
                            Text(
                              siteName,
                              style: TextStyle(
                                fontSize: 11,
                                color: shiftColor.withOpacity(0.75),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ] else
                      Text(
                        'ไม่มีตารางงาน',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.30),
                        ),
                      ),
                  ],
                ),
              ),
              if (_todayShift != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: shiftColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: shiftColor.withOpacity(0.30)),
                  ),
                  child: Text(
                    isOverride ? 'override' : 'weekly',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: shiftColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasShift && startTime != '--:--') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _timeChip(
                  icon: Icons.login_rounded,
                  label: 'เริ่มงาน',
                  time: startTime,
                  color: const Color(0xFF1D9E75),
                  bg: const Color(0xFF1D9E75).withOpacity(0.10),
                  borderColor: const Color(0xFF1D9E75).withOpacity(0.28),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _timeChip(
                  icon: Icons.logout_rounded,
                  label: 'เลิกงาน',
                  time: endTime,
                  color: const Color(0xFFE24B4A),
                  bg: const Color(0xFFE24B4A).withOpacity(0.10),
                  borderColor: const Color(0xFFE24B4A).withOpacity(0.28),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _timeChip({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
    required Color bg,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withOpacity(0.4),
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // ACTION BUTTON
  // ════════════════════════════════════════════

  Widget _actionButton({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: filled
              ? null
              : Border.all(color: color.withOpacity(0.55), width: 1.5),
          gradient: filled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.75)],
                )
              : null,
          color: filled ? null : Colors.transparent,
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: filled
                    ? Colors.white.withOpacity(0.20)
                    : color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(icon, color: filled ? Colors.white : color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : color,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: filled
                          ? Colors.white.withOpacity(0.70)
                          : color.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: filled
                  ? Colors.white.withOpacity(0.6)
                  : color.withOpacity(0.5),
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
                colors: [
                  Color(0x55000000),
                  Color(0xCC000000),
                  Color(0xF0000000),
                ],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -60, right: -60,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF29B6F6).withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // ── top bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                    child: Row(
                      children: [
                        const Text(
                          'TimeTrack',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                                onTap: () {
                                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                                    MaterialPageRoute(builder: (_) => const LoginPage()),
                                    (route) => false,
                                  );
                                },
                          child: Row(
                            children: [
                              Icon(Icons.logout_rounded,
                                  color: Colors.white.withOpacity(0.75),
                                  size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'ออกจากระบบ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.75),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── scrollable body ──
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // profile row
                          Row(
                            children: [
                              ScaleTransition(
                                scale: _pulseAnim,
                                child: Container(
                                  width: 62, height: 62,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFF29B6F6),
                                        width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF29B6F6)
                                            .withOpacity(0.40),
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: isLoadingUser
                                        ? Container(
                                            color:
                                                Colors.white.withOpacity(0.1),
                                            child:
                                                const CircularProgressIndicator(
                                              color: Color(0xFF29B6F6),
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : profilePhotoUrl.isNotEmpty
                                            ? Image.network(profilePhotoUrl,
                                                fit: BoxFit.cover,
                                                cacheWidth: 124,
                                                errorBuilder: (_, __, ___) =>
                                                    _defaultAvatar())
                                            : _defaultAvatar(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isLoadingUser ? 'กำลังโหลด...' : fullName,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusColor.withOpacity(0.18),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color:
                                                _statusColor.withOpacity(0.45),
                                            width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7, height: 7,
                                            decoration: BoxDecoration(
                                              color: _statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            status,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _statusColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // ── ปฏิทินกะ ──
                          GestureDetector(
                            onTap: () => setState(
                                () => _calendarExpanded = !_calendarExpanded),
                            child: Row(
                              children: [
                                Text(
                                  'ตารางกะเดือนนี้',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.45),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  _calendarExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: Colors.white.withOpacity(0.35),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildCalendar(),

                          const SizedBox(height: 16),

                          // ── นาฬิกา ──
                          const ClockWidget(),

                          const SizedBox(height: 16),

                          // ── ตารางกะวันนี้ ──
                          _buildTodayShiftCard(),

                          const SizedBox(height: 20),

                          // ── action buttons ──
                          Row(
                            children: [
                              Expanded(
                                child: _actionButton(
                                  label: 'Check In',
                                  sublabel: 'บันทึกเวลาเข้างาน',
                                  icon: Icons.login_rounded,
                                  color: const Color(0xFF29B6F6),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CheckInUI(
                                        employeeId: widget.employeeId,
                                        employeeName: widget.employeeName,
                                        employeePhone: widget.employeePhone,
                                      ),
                                    ),
                                  ).then((_) => loadUser()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _actionButton(
                                  label: 'Check Out',
                                  sublabel: 'บันทึกเวลาออกงาน',
                                  icon: Icons.logout_rounded,
                                  color: const Color(0xFF26C6DA),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CheckOutUI(
                                        employeeId: widget.employeeId,
                                        employeeName: widget.employeeName,
                                        employeePhone: widget.employeePhone,
                                      ),
                                    ),
                                  ).then((_) => loadUser()),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _actionButton(
                            label: 'โปรไฟล์',
                            sublabel: 'ดูและแก้ไขข้อมูลส่วนตัว',
                            icon: Icons.person_outline_rounded,
                            color: const Color(0xFF29B6F6),
                            filled: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmployeeProfileUI(
                                    employeeId: widget.employeeId),
                              ),
                            ).then((_) => loadUser()),
                          ),

                          const SizedBox(height: 12),

                          _actionButton(
                            label: 'ประวัติการลงเวลา',
                            sublabel: 'ดูรายการ Check In / Out ย้อนหลัง',
                            icon: Icons.history_rounded,
                            color: const Color(0xFF29B6F6),
                            filled: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmployeeHistoryUI(
                                    employeeId: widget.employeeId),
                              ),
                            ),
                          ),
                        ],
                    
                      ),
                      ]
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

  Widget _defaultAvatar() => Container(
        color: const Color(0xFF0277BD).withOpacity(0.5),
        child:
            const Icon(Icons.person_rounded, size: 36, color: Colors.white),
      );
}
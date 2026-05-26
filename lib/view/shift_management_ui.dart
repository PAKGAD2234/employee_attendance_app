import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShiftManagementUI extends StatefulWidget {
  const ShiftManagementUI({super.key});

  @override
  State<ShiftManagementUI> createState() => _ShiftManagementUIState();
}

class _ShiftManagementUIState extends State<ShiftManagementUI> {
  final supabase = Supabase.instance.client;

  List _shifts = [];
  List _workSites = [];
  bool _isLoading = true;

  // ── color palette (match AdminView) ─────────────────────
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

  // ── shift color options ──────────────────────────────────
  final List<Map<String, dynamic>> _colorOptions = [
    {'hex': '#185FA5', 'color': blue600,  'label': 'น้ำเงิน'},
    {'hex': '#1D9E75', 'color': teal400,  'label': 'เขียว'},
    {'hex': '#E24B4A', 'color': red400,   'label': 'แดง'},
    {'hex': '#BA7517', 'color': amber400, 'label': 'ส้ม'},
    {'hex': '#7F77DD', 'color': const Color(0xFF7F77DD), 'label': 'ม่วง'},
    {'hex': '#D4537E', 'color': const Color(0xFFD4537E), 'label': 'ชมพู'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final shifts = await supabase
          .from('shift_templates')
          .select('*, work_sites(name)')
          .eq('is_active', true)
          .order('start_time');
      final sites = await supabase.from('work_sites').select().order('name');
      if (mounted) {
        setState(() {
          _shifts = shifts;
          _workSites = sites;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) _showSnack('โหลดข้อมูลล้มเหลว: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════
  // FORM — เพิ่ม / แก้ไข กะ
  // ════════════════════════════════════════════

  void _openShiftForm({Map? shift}) {
    // init values
    final nameCtrl = TextEditingController(text: shift?['name'] ?? '');
    TimeOfDay startTime = _parseTime(shift?['start_time'] ?? '09:00');
    TimeOfDay endTime   = _parseTime(shift?['end_time']   ?? '18:00');
    int lateMin    = shift?['late_threshold_minutes'] ?? 15;
    int earlyMin   = shift?['early_checkin_minutes']  ?? 30;
    String selectedColor = shift?['color'] ?? '#185FA5';
    String? selectedSiteId = shift?['work_site_id']?.toString();

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
                  // handle bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: blue100, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),

                  // title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: blue50, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.schedule_rounded, color: blue600, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        shift != null ? 'แก้ไขกะงาน' : 'เพิ่มกะงานใหม่',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: blue800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ชื่อกะ
                  _label('ชื่อกะ *'),
                  const SizedBox(height: 6),
                  _textField(controller: nameCtrl, hint: 'เช่น กะเช้า, กะดึก', icon: Icons.label_outline),
                  const SizedBox(height: 14),

                  // เวลา
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('เวลาเริ่มงาน'),
                            const SizedBox(height: 6),
                            _timeTile(
                              time: startTime,
                              icon: Icons.login_rounded,
                              color: teal400,
                              bg: teal50,
                              onTap: () async {
                                final t = await showTimePicker(
                                    context: ctx, initialTime: startTime);
                                if (t != null) setModal(() => startTime = t);
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
                            _label('เวลาเลิกงาน'),
                            const SizedBox(height: 6),
                            _timeTile(
                              time: endTime,
                              icon: Icons.logout_rounded,
                              color: red400,
                              bg: red50,
                              onTap: () async {
                                final t = await showTimePicker(
                                    context: ctx, initialTime: endTime);
                                if (t != null) setModal(() => endTime = t);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ผ่อนผันสาย
                  _label('ผ่อนผันสาย (นาที)'),
                  const SizedBox(height: 6),
                  _counterRow(
                    icon: Icons.timer_outlined,
                    iconColor: amber400,
                    bg: amber50,
                    value: lateMin,
                    unit: 'นาที',
                    onDec: () { if (lateMin >= 5) setModal(() => lateMin -= 5); },
                    onInc: () => setModal(() => lateMin += 5),
                  ),
                  const SizedBox(height: 8),
                  _infoBox('เช็คอินหลัง ${_addMinutes(startTime, lateMin)} ถือว่าสาย',
                      amber400, amber50),
                  const SizedBox(height: 14),

                  // เช็คอินก่อนได้กี่นาที
                  _label('เช็คอินก่อนเวลาได้ (นาที)'),
                  const SizedBox(height: 6),
                  _counterRow(
                    icon: Icons.access_time_rounded,
                    iconColor: blue600,
                    bg: blue50,
                    value: earlyMin,
                    unit: 'นาที',
                    onDec: () { if (earlyMin >= 5) setModal(() => earlyMin -= 5); },
                    onInc: () => setModal(() => earlyMin += 5),
                  ),
                  const SizedBox(height: 8),
                  _infoBox('เช็คอินได้ตั้งแต่ ${_subMinutes(startTime, earlyMin)}',
                      blue600, blue50),
                  const SizedBox(height: 14),

                  // สี
                  _label('สีของกะ'),
                  const SizedBox(height: 8),
                  Row(
                    children: _colorOptions.map((opt) {
                      final isSelected = selectedColor == opt['hex'];
                      return GestureDetector(
                        onTap: () => setModal(() => selectedColor = opt['hex']),
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: opt['color'] as Color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: blue800, width: 3)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 16)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Site
                  _label('สาขา / บริษัท (ถ้ามี)'),
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
                        hint: const Text('ทุกสาขา',
                            style: TextStyle(color: gray400, fontSize: 13)),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text('ทุกสาขา',
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
                  const SizedBox(height: 22),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _saveShift(
                        ctx: ctx,
                        shiftId: shift?['id']?.toString(),
                        name: nameCtrl.text.trim(),
                        startTime: startTime,
                        endTime: endTime,
                        lateMin: lateMin,
                        earlyMin: earlyMin,
                        color: selectedColor,
                        siteId: selectedSiteId,
                      ),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text(
                        shift != null ? 'บันทึกการแก้ไข' : 'เพิ่มกะงาน',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
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

  Future<void> _saveShift({
    required BuildContext ctx,
    String? shiftId,
    required String name,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required int lateMin,
    required int earlyMin,
    required String color,
    String? siteId,
  }) async {
    if (name.isEmpty) {
      _showSnack('กรุณากรอกชื่อกะ', isError: true);
      return;
    }

    final payload = {
      'name': name,
      'start_time': _timeToStr(startTime),
      'end_time': _timeToStr(endTime),
      'late_threshold_minutes': lateMin,
      'early_checkin_minutes': earlyMin,
      'color': color,
      'work_site_id': siteId,
      'is_active': true,
    };

    try {
      if (shiftId != null) {
        await supabase.from('shift_templates').update(payload).eq('id', shiftId);
      } else {
        await supabase.from('shift_templates').insert(payload);
      }
      await _loadData();
      if (mounted) {
        Navigator.pop(ctx);
        _showSnack(shiftId != null ? '✅ แก้ไขกะสำเร็จ' : '✅ เพิ่มกะสำเร็จ');
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _deleteShift(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบกะ "$name" ใช่หรือไม่?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        // soft delete
        await supabase
            .from('shift_templates')
            .update({'is_active': false})
            .eq('id', id);
        await _loadData();
        _showSnack('ลบกะสำเร็จ');
      } catch (e) {
        _showSnack('Error: $e', isError: true);
      }
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
          onPressed: () => Navigator.maybePop(context),
        ),
        backgroundColor: blue800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('จัดการกะงาน',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: blue600))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: blue600,
              child: _shifts.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _shifts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _buildShiftCard(_shifts[i]),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openShiftForm(),
        backgroundColor: blue600,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('เพิ่มกะ',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration:
                const BoxDecoration(color: blue50, shape: BoxShape.circle),
            child:
                const Icon(Icons.schedule_rounded, size: 52, color: blue400),
          ),
          const SizedBox(height: 16),
          const Text('ยังไม่มีกะงาน',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: blue800)),
          const SizedBox(height: 6),
          const Text('กด "เพิ่มกะ" เพื่อสร้างกะงานแรก',
              style: TextStyle(fontSize: 13, color: gray400)),
        ],
      ),
    );
  }

  Widget _buildShiftCard(Map shift) {
    final shiftColor = _hexToColor(shift['color'] ?? '#185FA5');
    final shiftColorLight = shiftColor.withOpacity(0.12);
    final startStr = _formatTime(shift['start_time']);
    final endStr   = _formatTime(shift['end_time']);
    final siteName = shift['work_sites']?['name'];
    final lateMin  = shift['late_threshold_minutes'] ?? 15;
    final earlyMin = shift['early_checkin_minutes']  ?? 30;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue100),
      ),
      child: Column(
        children: [
          // ── header strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: shiftColorLight,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                      color: shiftColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shift['name'] ?? 'ไม่ระบุชื่อ',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: shiftColor),
                  ),
                ),
                if (siteName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on,
                            size: 10, color: shiftColor),
                        const SizedBox(width: 3),
                        Text(siteName,
                            style: TextStyle(
                                fontSize: 10,
                                color: shiftColor,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                // เวลาเริ่ม - เลิก
                Row(
                  children: [
                    _timeChip(startStr, Icons.login_rounded, teal400, teal50),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 14, color: gray400),
                    ),
                    _timeChip(endStr, Icons.logout_rounded, red400, red50),
                    const Spacer(),
                    // action buttons
                    _actionBtn(
                      Icons.edit_rounded,
                      blue50,
                      blue600,
                      () => _openShiftForm(shift: shift),
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      Icons.delete_outline_rounded,
                      red50,
                      red400,
                      () => _deleteShift(
                          shift['id'].toString(), shift['name'] ?? ''),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: blue100),
                const SizedBox(height: 10),

                // rules row
                Row(
                  children: [
                    _rulePill(
                      Icons.timer_outlined,
                      'สายหลัง $lateMin นาที',
                      amber400,
                      amber50,
                    ),
                    const SizedBox(width: 8),
                    _rulePill(
                      Icons.access_time_rounded,
                      'เช็คอินก่อนได้ $earlyMin นาที',
                      blue600,
                      blue50,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════════

  Widget _timeChip(
      String time, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(time,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _rulePill(
      IconData icon, String text, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, Color bg, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12, color: gray400, fontWeight: FontWeight.w500));

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
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
            borderSide: const BorderSide(color: blue100)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: blue100)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: blue600, width: 1.5)),
      ),
    );
  }

  Widget _timeTile({
    required TimeOfDay time,
    required IconData icon,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counterRow({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required int value,
    required String unit,
    required VoidCallback onDec,
    required VoidCallback onInc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: iconColor.withOpacity(0.2))),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text('$value $unit',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: iconColor)),
          const Spacer(),
          _counterBtn(Icons.remove, onDec),
          const SizedBox(width: 8),
          _counterBtn(Icons.add, onInc),
        ],
      ),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: blue100)),
          child: Icon(icon, size: 16, color: blue600),
        ),
      );

  Widget _infoBox(String text, Color color, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: color),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      );

  // ════════════════════════════════════════════
  // UTILS
  // ════════════════════════════════════════════

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    return TimeOfDay(
        hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _timeToStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _formatTime(String? t) {
    if (t == null) return '--:--';
    final parts = t.split(':');
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String _addMinutes(TimeOfDay t, int min) {
    final total = t.hour * 60 + t.minute + min;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String _subMinutes(TimeOfDay t, int min) {
    final total = t.hour * 60 + t.minute - min;
    final clamped = total < 0 ? total + 1440 : total;
    return '${(clamped ~/ 60).toString().padLeft(2, '0')}:${(clamped % 60).toString().padLeft(2, '0')}';
  }

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? red400 : teal400,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}
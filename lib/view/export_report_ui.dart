import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import 'package:supabase_flutter/supabase_flutter.dart';

/// ════════════════════════════════════════════════════════════
/// EXPORT REPORT — สรุปสถิติการเข้างานรายเดือน + Export CSV / PDF
/// ════════════════════════════════════════════════════════════
///
/// วิธีคำนวณ (แก้ไขได้ตามต้องการ):
/// - สำหรับพนักงานแต่ละคน ไล่ทีละวันในเดือนที่เลือก
///   1) ถ้ามี schedule_overrides ของวันนั้น -> ใช้ค่านั้น (ทับ pattern รายสัปดาห์)
///   2) ถ้าไม่มี override -> ใช้ employee_weekly_schedules ตาม day_of_week
///   3) ถ้าไม่มีทั้งคู่ -> ถือว่าเป็นวันหยุดของพนักงาน ไม่นับในสถิติเลย
/// - ถ้า override_type == 'leave' -> นับเป็น "ลา"
/// - ถ้าเป็นวันที่ "ควรทำงาน" (มี schedule แต่ไม่ใช่ leave):
///     - มี attendance ที่ checkin_time != null -> นับเป็น "วันทำงาน"
///         - ถ้า late == true -> นับ "สาย" เพิ่มด้วย
///         - ถ้ามี checkout_time -> บวกชั่วโมงทำงาน
///         - นับเป็น 1 กะ (Total Shifts)
///     - ไม่มี attendance -> นับเป็น "ขาดงาน"
class ExportReportUI extends StatefulWidget {
  const ExportReportUI({super.key});

  @override
  State<ExportReportUI> createState() => _ExportReportUIState();
}

class _ExportReportUIState extends State<ExportReportUI> {
  final supabase = Supabase.instance.client;

  // ── palette (เหมือนหน้าอื่นๆ ในแอป) ──────────────────────
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

  static const List<String> _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  String? _selectedSiteId; // null = ทั้งหมด

  List _workSites = [];
  bool _isLoading = true;
  bool _isExporting = false;

  List<EmployeeReportRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadWorkSites();
    await _loadReport();
  }

  Future<void> _loadWorkSites() async {
    try {
      final sites = await supabase.from('work_sites').select().order('name');
      if (mounted) setState(() => _workSites = sites);
    } catch (_) {}
  }

  String _getSiteName(String? siteId) {
    if (siteId == null) return '-';
    final site = _workSites.firstWhere(
      (s) => s['id'].toString() == siteId,
      orElse: () => <String, dynamic>{},
    );
    return site['name'] ?? '-';
  }

  // ════════════════════════════════════════════
  // LOAD + COMPUTE REPORT
  // ════════════════════════════════════════════

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      final year = _selectedYear;
      final month = _selectedMonth;
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final firstDay = '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay =
          '$year-${month.toString().padLeft(2, '0')}-${daysInMonth.toString().padLeft(2, '0')}';

      // 1) พนักงาน (กรองตามสาขาถ้าเลือกไว้)
      var empQuery = supabase
          .from('employees')
          .select('id, full_name, work_site_id, department, status')
          .eq('status', 'active');
      if (_selectedSiteId != null) {
        empQuery = empQuery.eq('work_site_id', _selectedSiteId!);
      }
      final employees = await empQuery.order('full_name');
      final empList = List<Map<String, dynamic>>.from(employees as List);
      final empIds = empList.map((e) => e['id'].toString()).toList();

      if (empIds.isEmpty) {
        if (mounted) {
          setState(() {
            _rows = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 2) weekly pattern ของพนักงานกลุ่มนี้
      final weeklies = await supabase
          .from('employee_weekly_schedules')
          .select('employee_id, day_of_week, shift_template_id')
          .isFilter('effective_until', null)
          .inFilter('employee_id', empIds);

      final weeklyMap = <String, Map<int, Map>>{};
      for (final row in (weeklies as List)) {
        final empId = row['employee_id'].toString();
        final dow = row['day_of_week'] as int;
        weeklyMap.putIfAbsent(empId, () => {});
        weeklyMap[empId]![dow] = row;
      }

      // 3) overrides ของเดือนนี้
      final overrides = await supabase
          .from('schedule_overrides')
          .select('employee_id, override_date, override_type, shift_template_id')
          .gte('override_date', firstDay)
          .lte('override_date', lastDay)
          .inFilter('employee_id', empIds);

      final overrideMap = <String, Map<String, Map>>{}; // empId -> dateStr -> row
      for (final row in (overrides as List)) {
        final empId = row['employee_id'].toString();
        final dateStr = row['override_date'].toString();
        overrideMap.putIfAbsent(empId, () => {});
        overrideMap[empId]![dateStr] = row;
      }

      // 4) attendance ของเดือนนี้
      final attendance = await supabase
          .from('attendance')
          .select('employee_id, work_date, checkin_time, checkout_time, late')
          .gte('work_date', firstDay)
          .lte('work_date', lastDay)
          .inFilter('employee_id', empIds);

      final attMap = <String, Map<String, Map>>{}; // empId -> dateStr -> row
      for (final row in (attendance as List)) {
        final empId = row['employee_id']?.toString();
        if (empId == null) continue;
        final dateStr = row['work_date']?.toString() ?? '';
        if (dateStr.isEmpty) continue;
        attMap.putIfAbsent(empId, () => {});
        attMap[empId]![dateStr] = row;
      }

      // 5) คำนวณทีละพนักงาน ทีละวัน
      final List<EmployeeReportRow> results = [];
      for (final emp in empList) {
        final empId = emp['id'].toString();
        final row = EmployeeReportRow(
          employeeId: empId,
          name: emp['full_name'] ?? '-',
          siteName: _getSiteName(emp['work_site_id']?.toString()),
        );

        for (int day = 1; day <= daysInMonth; day++) {
          final date = DateTime(year, month, day);
          final dateStr =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final dow = date.weekday % 7;

          final ov = overrideMap[empId]?[dateStr];
          final wk = weeklyMap[empId]?[dow];

          final hasSchedule = ov != null || wk != null;
          if (!hasSchedule) continue; // วันหยุดของพนักงาน ไม่นับ

          final isLeave = ov != null && ov['override_type'] == 'leave';
          if (isLeave) {
            row.leave++;
            continue;
          }

          // วันที่ควรทำงาน -> เช็ค attendance จริง
          final att = attMap[empId]?[dateStr];
          if (att != null && att['checkin_time'] != null) {
            row.workingDays++;
            row.totalShifts++;
            if (att['late'] == true) row.late++;
            if (att['checkout_time'] != null) {
              try {
                final inT = DateTime.parse(att['checkin_time']);
                final outT = DateTime.parse(att['checkout_time']);
                final hrs = outT.difference(inT).inMinutes / 60.0;
                if (hrs > 0) row.totalHours += hrs;
              } catch (_) {}
            }
          } else {
            row.absent++;
          }
        }

        results.add(row);
      }

      // เรียงชื่อ
      results.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          _rows = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _snack('โหลดรายงานล้มเหลว: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════
  // SUMMARY GETTERS
  // ════════════════════════════════════════════

  int get _totalEmployees => _rows.length;
  int get _totalWorking => _rows.fold(0, (s, r) => s + r.workingDays);
  int get _totalLate => _rows.fold(0, (s, r) => s + r.late);
  int get _totalLeave => _rows.fold(0, (s, r) => s + r.leave);
  int get _totalAbsent => _rows.fold(0, (s, r) => s + r.absent);
  double get _totalHours => _rows.fold(0.0, (s, r) => s + r.totalHours);
  int get _totalShifts => _rows.fold(0, (s, r) => s + r.totalShifts);
  double get _avgHours => _totalEmployees == 0 ? 0 : _totalHours / _totalEmployees;

  // ════════════════════════════════════════════
  // CSV EXPORT
  // ════════════════════════════════════════════

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    try {
      final monthLabel = '${_thaiMonths[_selectedMonth - 1]} ${_selectedYear + 543}';
      final buffer = StringBuffer();
      // BOM เพื่อให้ Excel อ่านภาษาไทยถูกต้อง
      buffer.write('\uFEFF');
      buffer.writeln(
        [
          'Employee Name',
          'Branch',
          'Month',
          'Working Days',
          'Late',
          'Leave',
          'Absent',
          'Total Hours',
          'Total Shifts',
        ].map(_csvCell).join(','),
      );
      for (final r in _rows) {
        buffer.writeln(
          [
            r.name,
            r.siteName,
            monthLabel,
            r.workingDays.toString(),
            r.late.toString(),
            r.leave.toString(),
            r.absent.toString(),
            r.totalHours.toStringAsFixed(2),
            r.totalShifts.toString(),
          ].map(_csvCell).join(','),
        );
      }

      final siteLabel = _selectedSiteId == null ? 'all' : _getSiteName(_selectedSiteId);
      final fileName =
          'attendance_report_${_selectedYear}_${_selectedMonth.toString().padLeft(2, '0')}_$siteLabel.csv'
              .replaceAll(' ', '_');

      if (kIsWeb) {
        final bytes = utf8.encode(buffer.toString());
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(buffer.toString(), encoding: utf8);
        await Share.shareXFiles([XFile(file.path)],
            text: 'รายงานการเข้างานเดือน $monthLabel');
      }
    } catch (e) {
      _snack('Export CSV ล้มเหลว: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  // ════════════════════════════════════════════
  // PDF EXPORT
  // ════════════════════════════════════════════

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final doc = pw.Document();
      final thaiFont = await _loadThaiFont();
      final thaiFontBold = await _loadThaiFont(bold: true);

      final monthLabel = '${_thaiMonths[_selectedMonth - 1]} ${_selectedYear + 543}';
      final siteLabel = _selectedSiteId == null ? 'ทุกสาขา' : _getSiteName(_selectedSiteId);
      final exportDate = DateTime.now();
      final exportDateStr =
          '${exportDate.day.toString().padLeft(2, '0')}/${exportDate.month.toString().padLeft(2, '0')}/${exportDate.year + 543}';

      final baseStyle = pw.TextStyle(font: thaiFont, fontSize: 10);
      final boldStyle = pw.TextStyle(font: thaiFontBold, fontSize: 10, fontWeight: pw.FontWeight.bold);

      // ── หน้าตาราง (แบ่งหน้าอัตโนมัติถ้ารายชื่อยาว) ──
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (ctx) => _pdfHeader(
            thaiFont: thaiFont,
            thaiFontBold: thaiFontBold,
            monthLabel: monthLabel,
            siteLabel: siteLabel,
            exportDateStr: exportDateStr,
            showOnlyOnFirstPage: ctx.pageNumber == 1,
          ),
          build: (ctx) => [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.6),
                1: pw.FlexColumnWidth(1.1),
                2: pw.FlexColumnWidth(0.9),
                3: pw.FlexColumnWidth(0.9),
                4: pw.FlexColumnWidth(0.9),
                5: pw.FlexColumnWidth(1.1),
                6: pw.FlexColumnWidth(0.9),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C447C)),
                  children: [
                    _pdfHeadCell('Employee', boldStyle.copyWith(color: PdfColors.white)),
                    _pdfHeadCell('Working Days', boldStyle.copyWith(color: PdfColors.white)),
                    _pdfHeadCell('Late', boldStyle.copyWith(color: PdfColors.white)),
                    _pdfHeadCell('Leave', boldStyle.copyWith(color: PdfColors.white)),
                    _pdfHeadCell('Absent', boldStyle.copyWith(color: PdfColors.white)),
                    _pdfHeadCell('Hours', boldStyle.copyWith(color: PdfColors.white)),
                    _pdfHeadCell('Shifts', boldStyle.copyWith(color: PdfColors.white)),
                  ],
                ),
                ..._rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  final rowBg = i.isEven ? PdfColors.white : const PdfColor.fromInt(0xFFF0F5FB);
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBg),
                    children: [
                      _pdfCell(r.name, baseStyle, align: pw.TextAlign.left),
                      _pdfCell('${r.workingDays}', baseStyle),
                      _pdfCell('${r.late}', baseStyle),
                      _pdfCell('${r.leave}', baseStyle),
                      _pdfCell('${r.absent}', baseStyle),
                      _pdfCell(r.totalHours.toStringAsFixed(1), baseStyle),
                      _pdfCell('${r.totalShifts}', baseStyle),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      );

      // ── หน้าสุดท้าย: Summary ──
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Summary', style: boldStyle.copyWith(fontSize: 18)),
              pw.SizedBox(height: 4),
              pw.Text('$monthLabel • $siteLabel', style: baseStyle.copyWith(color: PdfColors.grey700)),
              pw.SizedBox(height: 16),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  _pdfSummaryRow('Total Employees', '$_totalEmployees', baseStyle, boldStyle),
                  _pdfSummaryRow('Total Working Days', '$_totalWorking', baseStyle, boldStyle),
                  _pdfSummaryRow('Total Late', '$_totalLate', baseStyle, boldStyle),
                  _pdfSummaryRow('Total Leave', '$_totalLeave', baseStyle, boldStyle),
                  _pdfSummaryRow('Total Absent', '$_totalAbsent', baseStyle, boldStyle),
                  _pdfSummaryRow('Total Shifts', '$_totalShifts', baseStyle, boldStyle),
                  _pdfSummaryRow('Total Hours', _totalHours.toStringAsFixed(1), baseStyle, boldStyle),
                  _pdfSummaryRow('Average Hours / Employee', _avgHours.toStringAsFixed(1), baseStyle, boldStyle),
                ],
              ),
            ],
          ),
        ),
      );

      final bytes = await doc.save();
      final siteFile = _selectedSiteId == null ? 'all' : _getSiteName(_selectedSiteId);
      final fileName =
          'attendance_report_${_selectedYear}_${_selectedMonth.toString().padLeft(2, '0')}_$siteFile.pdf'
              .replaceAll(' ', '_');

      if (kIsWeb) {
        final blob = html.Blob([Uint8List.fromList(bytes)], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        anchor.remove();
        if (mounted) _snack('PDF ถูกดาวน์โหลดแล้ว');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], text: 'รายงานการเข้างานเดือน $monthLabel');
      }
    } catch (e) {
      _snack('Export PDF ล้มเหลว: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  pw.Widget _pdfHeader({
    required pw.Font thaiFont,
    required pw.Font thaiFontBold,
    required String monthLabel,
    required String siteLabel,
    required String exportDateStr,
    required bool showOnlyOnFirstPage,
  }) {
    if (!showOnlyOnFirstPage) {
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text('OpMatch — รายงานการเข้างาน ($monthLabel)',
            style: pw.TextStyle(font: thaiFont, fontSize: 9, color: PdfColors.grey600)),
      );
    }
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('OpMatch',
                  style: pw.TextStyle(
                      font: thaiFontBold, fontSize: 22, color: const PdfColor.fromInt(0xFF0C447C))),
              pw.Text('Export: $exportDateStr',
                  style: pw.TextStyle(font: thaiFont, fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('รายงานสรุปการเข้างานพนักงานประจำเดือน',
              style: pw.TextStyle(font: thaiFontBold, fontSize: 14)),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _pdfInfoChip('เดือน', monthLabel, thaiFont, thaiFontBold),
              pw.SizedBox(width: 8),
              _pdfInfoChip('สาขา', siteLabel, thaiFont, thaiFontBold),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: PdfColors.grey400, thickness: 0.7),
        ],
      ),
    );
  }

  pw.Widget _pdfInfoChip(String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFE6F1FB),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 9, color: const PdfColor.fromInt(0xFF0C447C))),
        ],
      ),
    );
  }

  pw.Widget _pdfHeadCell(String text, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
      );

  pw.Widget _pdfCell(String text, pw.TextStyle style, {pw.TextAlign align = pw.TextAlign.center}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(text, style: style, textAlign: align),
      );

  pw.TableRow _pdfSummaryRow(String label, String value, pw.TextStyle base, pw.TextStyle bold) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Text(label, style: base),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Text(value, style: bold, textAlign: pw.TextAlign.right),
        ),
      ],
    );
  }

  /// โหลดฟอนต์ไทยจาก asset เพื่อให้ PDF แสดงตัวอักษรไทยได้ถูกต้อง
  Future<pw.Font> _loadThaiFont({bool bold = false}) async {
    const regularAsset = 'assets/fonts/Sarabun-Regular.ttf';
    const boldAsset = 'assets/fonts/Sarabun-Bold.ttf';
    final assetPath = bold ? boldAsset : regularAsset;

    try {
      if (kIsWeb) {
        final request = await html.HttpRequest.request(
          assetPath,
          responseType: 'arraybuffer',
        );
        final buffer = request.response as ByteBuffer;
        return pw.Font.ttf(ByteData.view(buffer));
      }

      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (e) {
      // ถ้า asset โหลดไม่ได้ ให้ fallback เป็นฟอนต์ PDF ในตัว
      return bold ? pw.Font.helveticaBold() : pw.Font.helvetica();
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
        title: const Text('Export Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _loadReport, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: blue600))
                : RefreshIndicator(
                    onRefresh: _loadReport,
                    color: blue600,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      children: [
                        _buildSummaryGrid(),
                        const SizedBox(height: 18),
                        _buildSectionTitle(
                            'แยกตามพนักงาน (${_rows.length} คน)'),
                        const SizedBox(height: 10),
                        _buildEmployeeTable(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildExportBar(),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: blue100)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dropdownShell(
                  child: DropdownButton<int>(
                    value: _selectedMonth,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(value: i + 1, child: Text(_thaiMonths[i])),
                    ),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedMonth = v);
                      _loadReport();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdownShell(
                  child: DropdownButton<int>(
                    value: _selectedYear,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
                    items: [
                      DateTime.now().year - 1,
                      DateTime.now().year,
                      DateTime.now().year + 1,
                    ]
                        .map((y) => DropdownMenuItem(value: y, child: Text('${y + 543}')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedYear = v);
                      _loadReport();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _dropdownShell(
            child: DropdownButton<String?>(
              value: _selectedSiteId,
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: Colors.white,
              style: const TextStyle(color: Color(0xFF1a2a3a), fontSize: 13),
              hint: const Text('ทุกสาขา', style: TextStyle(color: gray400, fontSize: 13)),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    children: [
                      Icon(Icons.business_rounded, size: 15, color: blue600),
                      SizedBox(width: 8),
                      Text('ทุกสาขา', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                ..._workSites.map((s) => DropdownMenuItem<String>(
                      value: s['id'].toString(),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 15, color: teal400),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s['name'] ?? '-', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )),
              ],
              onChanged: (v) {
                setState(() => _selectedSiteId = v);
                _loadReport();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownShell({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: blue50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: blue100),
        ),
        child: child,
      );

  Widget _buildSummaryGrid() {
    final items = [
      ['พนักงานทั้งหมด', '$_totalEmployees', Icons.people_rounded, blue600, blue50],
      ['วันมาทำงาน', '$_totalWorking', Icons.check_circle_outline, teal400, teal50],
      ['วันมาสาย', '$_totalLate', Icons.warning_amber_rounded, amber400, amber50],
      ['วันลา', '$_totalLeave', Icons.beach_access_rounded, const Color(0xFF7F77DD), const Color(0xFFEDEBFB)],
      ['วันขาดงาน', '$_totalAbsent', Icons.cancel_outlined, red400, red50],
      ['ชั่วโมงรวม', _totalHours.toStringAsFixed(1), Icons.schedule_rounded, blue600, blue50],
      ['เฉลี่ยชม./คน', _avgHours.toStringAsFixed(1), Icons.bar_chart_rounded, teal400, teal50],
      ['กะทั้งหมด', '$_totalShifts', Icons.event_available_rounded, amber400, amber50],
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: items.map((it) {
        final color = it[3] as Color;
        final bg = it[4] as Color;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(it[2] as IconData, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it[1] as String,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
                    Text(it[0] as String,
                        style: const TextStyle(fontSize: 10, color: gray400),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmployeeTable() {
    if (_rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: blue100),
        ),
        child: Center(
          child: Text('ไม่มีข้อมูลในเดือน/สาขาที่เลือก', style: TextStyle(color: gray400)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue100),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(blue50),
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('ชื่อพนักงาน', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            DataColumn(label: Text('สาขา', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            DataColumn(label: Text('ทำงาน', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('สาย', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('ลา', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('ขาด', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('ชม.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('กะ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
          ],
          rows: _rows.map((r) {
            return DataRow(cells: [
              DataCell(Text(r.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              DataCell(Text(r.siteName, style: const TextStyle(fontSize: 11, color: gray400))),
              DataCell(Text('${r.workingDays}', style: const TextStyle(fontSize: 12, color: teal400, fontWeight: FontWeight.w600))),
              DataCell(Text('${r.late}', style: const TextStyle(fontSize: 12, color: amber400, fontWeight: FontWeight.w600))),
              DataCell(Text('${r.leave}', style: const TextStyle(fontSize: 12, color: Color(0xFF7F77DD), fontWeight: FontWeight.w600))),
              DataCell(Text('${r.absent}', style: const TextStyle(fontSize: 12, color: red400, fontWeight: FontWeight.w600))),
              DataCell(Text(r.totalHours.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
              DataCell(Text('${r.totalShifts}', style: const TextStyle(fontSize: 12))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: blue800));

  Widget _buildExportBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: blue100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_isExporting || _rows.isEmpty) ? null : _exportCsv,
                icon: const Icon(Icons.table_chart_rounded, size: 17),
                label: const Text('Export CSV', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: teal400,
                  side: BorderSide(color: teal400),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_isExporting || _rows.isEmpty) ? null : _exportPdf,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 17),
                label: const Text('Export PDF', style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
}

/// ข้อมูลสรุปรายพนักงาน 1 คน สำหรับเดือนที่เลือก
class EmployeeReportRow {
  final String employeeId;
  final String name;
  final String siteName;
  int workingDays = 0;
  int late = 0;
  int leave = 0;
  int absent = 0;
  double totalHours = 0;
  int totalShifts = 0;

  EmployeeReportRow({
    required this.employeeId,
    required this.name,
    required this.siteName,
  });
}
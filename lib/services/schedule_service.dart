// lib/services/schedule_service.dart  (ไฟล์ใหม่)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduleService {
  final SupabaseClient _db;
  ScheduleService(this._db);

  /// คืน effective schedule สำหรับพนักงาน 1 คน ใน 1 วัน
  /// Priority: Override > Weekly > null (ไม่มีตาราง)
  Future<EffectiveSchedule?> getEffectiveSchedule({
    required String employeeId,
    required DateTime date,
  }) async {
    // ── 1. ตรวจ Override ก่อนเสมอ ──────────────────────────
    final override = await _db
        .from('schedule_overrides')
        .select('*, shift_templates(*), work_sites(*)')
        .eq('employee_id', employeeId)
        .eq('override_date', date.toIso8601String().substring(0, 10))
        .maybeSingle();

    if (override != null) {
      return EffectiveSchedule.fromOverride(override, date);
    }

    // ── 2. ตรวจ Weekly Schedule ─────────────────────────────
    final dayOfWeek = date.weekday % 7; // dart weekday: Mon=1, Sun=7 → 0-6
    final weekly = await _db
        .from('employee_weekly_schedules')
        .select('*, shift_templates(*), work_sites(*)')
        .eq('employee_id', employeeId)
        .eq('day_of_week', dayOfWeek)
        .lte('effective_from', date.toIso8601String().substring(0, 10))
        .or('effective_until.is.null,effective_until.gte.${date.toIso8601String().substring(0, 10)}')
        .order('effective_from', ascending: false)
        .limit(1)
        .maybeSingle();

    if (weekly != null) {
      return EffectiveSchedule.fromWeekly(weekly, date);
    }

    // ── 3. ไม่มีตาราง ───────────────────────────────────────
    return null;
  }

  /// ดึง schedule ทั้งเดือนสำหรับ calendar view
  Future<Map<String, EffectiveSchedule>> getMonthlySchedule({
    required String employeeId,
    required int year,
    required int month,
  }) async {
    final result = <String, EffectiveSchedule>{};
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // batch query แทน loop
    final firstDay = '$year-${month.toString().padLeft(2,'0')}-01';
    final lastDay  = '$year-${month.toString().padLeft(2,'0')}-${daysInMonth.toString().padLeft(2,'0')}';

    final overrides = await _db
        .from('schedule_overrides')
        .select('*, shift_templates(*), work_sites(*)')
        .eq('employee_id', employeeId)
        .gte('override_date', firstDay)
        .lte('override_date', lastDay);

    final weeklies = await _db
        .from('employee_weekly_schedules')
        .select('*, shift_templates(*), work_sites(*)')
        .eq('employee_id', employeeId)
        .lte('effective_from', lastDay)
        .or('effective_until.is.null,effective_until.gte.$firstDay');

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final dateStr = date.toIso8601String().substring(0, 10);
      final dayOfWeek = date.weekday % 7;

      final ovList = (overrides as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((o) => o['override_date'] == dateStr)
          .toList();
      final ov = ovList.isNotEmpty ? ovList.first : null;
      if (ov != null) {
        result[dateStr] = EffectiveSchedule.fromOverride(ov, date);
        continue;
      }

      final wk = (weeklies as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((w) => w['day_of_week'] == dayOfWeek)
          .toList()
        ..sort((a, b) => (b['effective_from'] as String).compareTo(a['effective_from'] as String));
      if (wk.isNotEmpty) {
        result[dateStr] = EffectiveSchedule.fromWeekly(wk.first, date);
      }
    }
    return result;
  }
}

// ── Data model ──────────────────────────────────────────────
class EffectiveSchedule {
  final String source;         // 'override' | 'weekly'
  final String? overrideType;  // 'special' | 'ot' | 'leave' | 'substitute'
  final TimeOfDay startTime;
  final TimeOfDay? endTime;
  final int lateThresholdMinutes;
  final int earlyCheckinMinutes;
  final String? siteName;
  final String? shiftName;
  final String color;
  final String? note;
  final bool isOff;            // override กะ = null → วันหยุด

  EffectiveSchedule({
    required this.source,
    this.overrideType,
    required this.startTime,
    this.endTime,
    required this.lateThresholdMinutes,
    required this.earlyCheckinMinutes,
    this.siteName,
    this.shiftName,
    this.color = '#185FA5',
    this.note,
    this.isOff = false,
  });

  factory EffectiveSchedule.fromOverride(Map data, DateTime date) {
    final shift = data['shift_templates'];
    final hasShift = shift != null;
    final startStr = data['custom_start_time'] ?? shift?['start_time'];
    return EffectiveSchedule(
      source: 'override',
      overrideType: data['override_type'],
      startTime: _parseTime(startStr ?? '00:00'),
      endTime: _parseTime(data['custom_end_time'] ?? shift?['end_time'] ?? '00:00'),
      lateThresholdMinutes: shift?['late_threshold_minutes'] ?? 15,
      earlyCheckinMinutes:  shift?['early_checkin_minutes']  ?? 30,
      siteName:  data['work_sites']?['name'],
      shiftName: hasShift ? shift['name'] : null,
      color:     shift?['color'] ?? '#E24B4A',
      note:      data['note'],
      isOff:     !hasShift && data['override_type'] == 'leave',
    );
  }

  factory EffectiveSchedule.fromWeekly(Map data, DateTime date) {
    final shift = data['shift_templates'];
    final startStr = data['custom_start_time'] ?? shift?['start_time'];
    return EffectiveSchedule(
      source:    'weekly',
      startTime: _parseTime(startStr ?? '09:00'),
      endTime:   _parseTime(data['custom_end_time'] ?? shift?['end_time'] ?? '18:00'),
      lateThresholdMinutes: shift?['late_threshold_minutes'] ?? 15,
      earlyCheckinMinutes:  shift?['early_checkin_minutes']  ?? 30,
      siteName:  data['work_sites']?['name'],
      shiftName: shift?['name'],
      color:     shift?['color'] ?? '#185FA5',
    );
  }

  static TimeOfDay _parseTime(String t) {
    final p = t.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
}
import 'package:employee_attendance_app/services/schedule_service.dart';
import 'package:employee_attendance_app/utils/attendance_schedule_utils.dart';
import 'package:employee_attendance_app/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses effective override schedule instead of employee default', () {
    final now = DateTime(2026, 7, 7, 13, 27);
    final effectiveSchedule = EffectiveSchedule(
      source: 'override',
      startTime: const TimeOfDay(hour: 13, minute: 30),
      lateThresholdMinutes: 0,
      earlyCheckinMinutes: 30,
    );

    final resolved = resolveAttendanceScheduleForCheckIn(
      now: now,
      effectiveSchedule: effectiveSchedule,
      fallbackWorkStartTime: '09:30',
      fallbackLateThresholdMinutes: 15,
    );

    expect(resolved.workStart.hour, 13);
    expect(resolved.workStart.minute, 30);
    expect(resolved.lateThresholdMinutes, 0);
  });

  test('falls back to employee defaults when no effective schedule exists', () {
    final now = DateTime(2026, 7, 7, 13, 27);

    final resolved = resolveAttendanceScheduleForCheckIn(
      now: now,
      effectiveSchedule: null,
      fallbackWorkStartTime: '09:30',
      fallbackLateThresholdMinutes: 15,
    );

    expect(resolved.workStart.hour, 9);
    expect(resolved.workStart.minute, 30);
    expect(resolved.lateThresholdMinutes, 15);
  });

  test('stores attendance timestamps as UTC minus seven hours from Thai time', () {
    final thaiTime = DateTime(2026, 7, 10, 9, 0, 0);
    final stored = formatAttendanceStorageDateTime(thaiTime);
    final parsed = parseAttendanceDateTime(stored);

    expect(stored, '2026-07-10T02:00:00.000Z');
    expect(parsed, DateTime.utc(2026, 7, 10, 9, 0, 0));
  });
}

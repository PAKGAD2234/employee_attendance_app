import 'package:flutter/material.dart';
import '../services/schedule_service.dart';

class ResolvedAttendanceSchedule {
  final DateTime workStart;
  final int lateThresholdMinutes;

  const ResolvedAttendanceSchedule({
    required this.workStart,
    required this.lateThresholdMinutes,
  });
}

ResolvedAttendanceSchedule resolveAttendanceScheduleForCheckIn({
  required DateTime now,
  required EffectiveSchedule? effectiveSchedule,
  required String fallbackWorkStartTime,
  required int fallbackLateThresholdMinutes,
}) {
  final startTime = effectiveSchedule?.startTime ?? _parseTime(fallbackWorkStartTime);
  final lateThreshold =
      effectiveSchedule?.lateThresholdMinutes ?? fallbackLateThresholdMinutes;

  return ResolvedAttendanceSchedule(
    workStart: DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    ),
    lateThresholdMinutes: lateThreshold,
  );
}

TimeOfDay _parseTime(String value) {
  final parts = value.split(':');
  return TimeOfDay(
    hour: int.parse(parts[0]),
    minute: int.parse(parts[1]),
  );
}

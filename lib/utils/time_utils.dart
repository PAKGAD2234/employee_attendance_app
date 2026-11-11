String _pad(int value, {int width = 2}) => value.toString().padLeft(width, '0');

/// แปลง DateTime (UTC หรือมี timezone อื่น) ให้เป็นเวลาไทย (+7) แบบตายตัว
/// ใช้ตอนที่ "แน่ใจ" ว่า input เป็น UTC จริง เช่นจาก DateTime.now().toUtc()
DateTime toBangkokDateTime(DateTime value) {
  return value.toUtc().add(const Duration(hours: 7));
}

/// เก็บเวลาไทยตามค่าบนหน้าปัดโดยไม่แปลงเป็น UTC
/// Google Sheets ไม่มี timezone ต่อเซลล์ จึงเก็บเป็นเวลาไทยแบบไม่มี timezone marker
String formatAttendanceStorageDateTime(DateTime value) {
  final milli = value.millisecond.toString().padLeft(3, '0');
  return '${value.year.toString().padLeft(4, '0')}-${_pad(value.month)}-${_pad(value.day)}'
      'T${_pad(value.hour)}:${_pad(value.minute)}:${_pad(value.second)}.${milli}';
}

/// อ่านค่าเวลาที่ดึงมาจาก DB (attendance.checkin_time / checkout_time)
/// แล้วคืนค่าเป็น "เวลาไทยที่ถูกต้อง" เสมอ ไม่ว่าเครื่อง/เบราว์เซอร์ที่รันแอป
/// จะตั้ง timezone เป็นอะไรก็ตาม (ห้ามอิง DateTime.timeZoneOffset ของเครื่องผู้ใช้
/// เด็ดขาด เพราะนั่นคือสาเหตุที่ทำให้เวลาบวกเพี้ยน +7 ชม. บนเครื่อง/เซิร์ฟเวอร์
/// ที่ตั้ง timezone เป็น UTC)
DateTime parseAttendanceDateTime(String isoString) {
  final hasZ = isoString.endsWith('Z');
  final hasOffset = RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(isoString);

  if (hasZ || hasOffset) {
    // รองรับข้อมูลเดิมที่บันทึกเป็น UTC โดยลบ 7 ชั่วโมง
    final utcInstant = DateTime.parse(isoString).toUtc();
    return utcInstant.add(const Duration(hours: 7));
  }

  // ไม่มี timezone marker -> ค่าที่เก็บใน DB เป็นเวลาไทย (naive) อยู่แล้ว
  // อ่านค่าตรงๆ ห้ามบวก/ลบเพิ่มอีก
  return DateTime.parse(isoString);
}

String formatAttendanceTime(String? isoString, {String fallback = '--:--'}) {
  if (isoString == null || isoString.isEmpty) return fallback;
  try {
    final dt = parseAttendanceDateTime(isoString);
    return '${_pad(dt.hour)}:${_pad(dt.minute)}';
  } catch (_) {
    return fallback;
  }
}

String formatAttendanceDate(String? isoString, {String fallback = '-'}) {
  if (isoString == null || isoString.isEmpty) return fallback;
  try {
    final dt = parseAttendanceDateTime(isoString);
    return '${_pad(dt.day)}/${_pad(dt.month)}/${dt.year}';
  } catch (_) {
    return fallback;
  }
}
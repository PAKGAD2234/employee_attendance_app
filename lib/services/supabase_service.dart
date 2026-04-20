import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  late SupabaseClient _client;

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  void initialize(SupabaseClient client) {
    _client = client;
  }

  SupabaseClient get client => _client;

  // ดึงข้อมูลพนักงานทั้งหมด
  Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .order('full_name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching employees: $e');
      rethrow;
    }
  }

  // ดึงข้อมูล attendance ของพนักงานหนึ่งคน
  Future<List<Map<String, dynamic>>> getEmployeeAttendance(String employeeId) async {
    try {
      final response = await _client
          .from('attendance')
          .select()
          .eq('employee_id', employeeId)
          .order('work_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching attendance: $e');
      rethrow;
    }
  }

  // ดึงข้อมูล attendance ทั้งหมดพร้อมข้อมูลพนักงาน
  Future<List<Map<String, dynamic>>> getAllAttendance() async {
    try {
      final response = await _client
          .from('attendance')
          .select('*, employees(full_name, email, department)')
          .order('work_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching all attendance: $e');
      rethrow;
    }
  }

  // ดึงข้อมูล attendance ตามวันที่
  Future<List<Map<String, dynamic>>> getAttendanceByDate(String date) async {
    try {
      final response = await _client
          .from('attendance')
          .select('*, employees(full_name, email, department)')
          .eq('work_date', date)
          .order('checkin_time', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching attendance by date: $e');
      rethrow;
    }
  }

  // ดึง URL ของภาพจาก storage
  String getImageUrl(String fileName) {
    try {
      final url = _client.storage
          .from('attendance')
          .getPublicUrl(fileName);
      return url;
    } catch (e) {
      print('Error getting image URL: $e');
      return '';
    }
  }

  // ดึง URL ของรูปโปรไฟล์จาก storage
  String getProfilePhotoUrl(String? photoValue) {
  if (photoValue == null || photoValue.isEmpty) return '';

  if (photoValue.startsWith('http')) {
    return photoValue;
  }

  try {
    final url = _client.storage
        .from('attendance')
        .getPublicUrl(photoValue);

    return url;
  } catch (e) {
    print('Error getting profile photo URL: $e');
    return '';
  }
} // ✅ ปิด function แค่นี้พอ

  // ดึงข้อมูล attendance พร้อมข้อมูลพนักงาน
  Future<List<Map<String, dynamic>>> getAttendanceWithImages() async {
    try {
      final response = await _client
          .from('attendance')
          .select('*, employees(full_name, email, department)')
          .order('work_date', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching attendance with images: $e');
      rethrow;
    }
  }

  // ค้นหาพนักงานตามชื่อหรืออีเมล
  Future<List<Map<String, dynamic>>> searchEmployees(String query) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .or('full_name.ilike.%$query%,email.ilike.%$query%');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching employees: $e');
      rethrow;
    }
  }

  // ค้นหา attendance ตามสถานะ
  Future<List<Map<String, dynamic>>> getAttendanceByStatus(String status) async {
    try {
      final response = await _client
          .from('attendance')
          .select('*, employees(full_name, email, department)')
          .eq('status', status)
          .order('work_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching attendance by status: $e');
      rethrow;
    }
  }

  // ดึงข้อมูล late attendance (สายเข้า)
  Future<List<Map<String, dynamic>>> getLateAttendance() async {
    try {
      final response = await _client
          .from('attendance')
          .select('*, employees(full_name, email, department)')
          .eq('late', true)
          .order('work_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching late attendance: $e');
      rethrow;
    }
  }

  // ดึงข้อมูลสรุปของพนักงาน (จำนวนวันทำงาน, สาย, ลา)
  Future<Map<String, dynamic>?> getEmployeeSummary(String employeeId) async {
    try {
      final response = await _client
          .from('attendance')
          .select()
          .eq('employee_id', employeeId);
      
      final attendanceRecords = List<Map<String, dynamic>>.from(response);
      
      final totalDays = attendanceRecords.length;
      final lateDays = attendanceRecords.where((record) => record['late'] == true).length;
      
      return {
        'total_days': totalDays,
        'late_days': lateDays,
        'on_time_days': totalDays - lateDays,
      };
    } catch (e) {
      print('Error fetching employee summary: $e');
      rethrow;
    }
  }

  // ============== EMPLOYEE MANAGEMENT ==============

  // สร้างพนักงานใหม่ (Admin only)
  Future<Map<String, dynamic>> createEmployee({
    required String fullName,
    String? englishName,
    required String phone,
    required String department,
    String? employeeCode,
  }) async {
    try {
      // สร้าง username จากชื่ออังกฤษ ถ้ามี ถ้าไม่มีก็ใช้ชื่อเต็ม
      final username = _generateUsername(englishName?.isNotEmpty == true ? englishName! : fullName);
      final password = _generatePassword();
      final email = '$username@attendance.local';

      // สร้างในตาราง employees
      final response = await _client.from('employees').insert({
        'full_name': fullName,
        'english_name': englishName,
        'email': email,
        'phone': phone,
        'username': username,
        'password': password,
        'employee_code': employeeCode ?? _generateEmployeeCode(),
        'role': 'employee',
        'department': department,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      }).select();

      if (response.isNotEmpty) {
        return {
          'success': true,
          'employee': response[0],
          'username': username,
          'password': password,
          'message': 'สร้างพนักงานสำเร็จ'
        };
      } else {
        throw Exception('Failed to create employee');
      }
    } catch (e) {
      print('Error creating employee: $e');
      rethrow;
    }
  }

  // ลบพนักงาน (Soft delete - เปลี่ยน status เป็น inactive)
  Future<void> deleteEmployee(String employeeId) async {
  try {
    await _client
        .from('employees')
        .update({'status': 'inactive'})
        .eq('id', employeeId)
        .eq('status', 'active'); // 🔥 เพิ่มตรงนี้
  } catch (e) {
    print('Error deleting employee: $e');
    rethrow;
  }
}

  // แก้ไขข้อมูลพนักงาน
  Future<Map<String, dynamic>> updateEmployee(
    String employeeId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _client
          .from('employees')
          .update(data)
          .eq('id', employeeId)
          .select();

      if (response.isNotEmpty) {
        return response[0];
      } else {
        throw Exception('Failed to update employee');
      }
    } catch (e) {
      print('Error updating employee: $e');
      rethrow;
    }
  }

  // ยืนยันตัวตน (login) ด้วย username หรือ email และ password
  Future<Map<String, dynamic>?> verifyLogin(
    String usernameOrEmail,
    String password,
  ) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .or('username.eq.$usernameOrEmail,email.eq.$usernameOrEmail')
          .eq('password', password)
          .eq('status', 'active')
          .maybeSingle();

      if (response != null) {
        return response;
      } else {
        return null;
      }
    } catch (e) {
      print('Error verifying login: $e');
      rethrow;
    }
  }

  // ดึงข้อมูลพนักงาน โดย employee id
  Future<Map<String, dynamic>?> getEmployee(String employeeId) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .eq('id', employeeId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error fetching employee: $e');
      rethrow;
    }
  }

  // ดึงข้อมูลพนักงาน โดย username
  Future<Map<String, dynamic>?> getEmployeeByUsername(String username) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .eq('username', username)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error fetching employee by username: $e');
      rethrow;
    }
  }

  // เปลี่ยนรหัสผ่าน
  Future<void> changePassword(String employeeId, String newPassword) async {
    try {
      await _client
          .from('employees')
          .update({'password': newPassword})
          .eq('id', employeeId);
    } catch (e) {
      print('Error changing password: $e');
      rethrow;
    }
  }

  // ============== HELPER FUNCTIONS ==============

  // สร้าง username จากชื่อ (เช่น "สมชาย สมิทธิ์" → "somchai.s001")
  String _generateUsername(String nameForUsername) {
    final cleanName = nameForUsername.trim().split(' ').first.toLowerCase();
    final base = cleanName.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final randomDigits = (Random().nextInt(9000) + 1000).toString();
    if (base.isEmpty) {
      return 'user$randomDigits';
    }
    return '$base$randomDigits';
  }

  // สร้าง password แบบสุ่ม (เช่น "Emp12345")
  String _generatePassword() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String result = 'Emp';
    for (int i = 0; i < 5; i++) {
      result += chars[random.hashCode % chars.length];
    }
    return result;
  }

  // สร้าง employee code (เช่น "EMP001", "EMP002")
  String _generateEmployeeCode() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
    return 'EMP$timestamp';
  }
}

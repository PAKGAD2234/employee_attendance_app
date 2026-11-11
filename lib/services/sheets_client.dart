// lib/services/sheets_client.dart
//
// SheetsClient: ตัวแทนของ supabase_flutter ที่คุยกับ Google Apps Script
// ออกแบบให้หน้าตาการเรียกเหมือน Supabase เดิมมากที่สุด เช่น
//   SheetsClient.instance.from('employees').select('*, work_sites(name)').eq('id', id)
//
// หมายเหตุ:
// - ส่ง POST แบบ text/plain (เลี่ยง CORS preflight บนเว็บ)
// - บนมือถือ Apps Script ตอบ POST ด้วย 302 ต้องตามไปที่ Location ด้วย GET เอง
//   (ส่วนบนเว็บ เบราว์เซอร์ตามให้เอง)
// - ข้อความ error จากเซิร์ฟเวอร์ถูกแปลงเป็น SheetsException (มี .code เช่น 23505, 23503)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// ============================================================
// Exception
// ============================================================

/// แทน PostgrestException ของ Supabase (มี message, code, details, hint)
class SheetsException implements Exception {
  const SheetsException(this.message, {this.code, this.details, this.hint});

  final String message;
  final String? code;
  final String? details;
  final String? hint;

  @override
  String toString() => 'SheetsException(code: $code, message: $message)';
}

// ============================================================
// Client
// ============================================================

class SheetsClient {
  SheetsClient._(this.url, this.apiKey, this.timeout);

  static SheetsClient? _instance;

  /// เรียกครั้งเดียวใน main() ก่อน runApp
  static SheetsClient initialize({
    required String url,
    required String apiKey,
    Duration timeout = const Duration(seconds: 45),
  }) {
    return _instance = SheetsClient._(url, apiKey, timeout);
  }

  /// ใช้แทน Supabase.instance.client
  static SheetsClient get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('ยังไม่ได้เรียก SheetsClient.initialize(...) ใน main()');
    }
    return i;
  }

  final String url;
  final String apiKey;
  final Duration timeout;

  final http.Client _http = http.Client();

  /// จำ URL รูปที่เพิ่งอัปโหลด เพื่อให้ getPublicUrl(path) ตอบได้ทันที
  final Map<String, String> _uploadedUrls = {};

  SheetsQueryBuilder from(String table) => SheetsQueryBuilder._(this, table);

  late final SheetsStorage storage = SheetsStorage._(this);
  late final SheetsFunctions functions = SheetsFunctions._(this);

  /// เช็กว่าเซิร์ฟเวอร์ตอบและ API_KEY ถูกต้อง
  Future<bool> ping() async {
    final d = await _call({'op': 'ping'});
    return d is Map && d['ok'] == true;
  }

  // ----------------------------------------------------------
  // รูปจาก Drive (ส่งกลับเป็น base64 ผ่าน op get_photo เพื่อเลี่ยง CORS บนเว็บ)
  // ----------------------------------------------------------

  final Map<String, Uint8List> _photoCache = {};
  final Map<String, Future<Uint8List>> _photoInflight = {};
  int _photoActive = 0;
  final List<Completer<void>> _photoWaiters = [];
  static const int _maxPhotoConcurrency = 2;

  static final RegExp _bareId = RegExp(r'^[A-Za-z0-9_-]{10,}$');

  /// true ถ้าค่านี้เป็นลิงก์/รหัสรูปของ Drive ที่ fetchPhoto อ่านได้
  static bool isDrivePhoto(String? value) => extractDriveId(value) != null;

  /// แยก fileId จาก: drive.google.com/thumbnail?id=..., lh3.googleusercontent.com/d/...,
  /// drive.google.com/file/d/.../view, drive.google.com/open?id=... หรือรหัสล้วน
  /// คืน null ถ้าเป็นลิงก์ภายนอกอื่น (เช่น Supabase)
  static String? extractDriveId(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    if (!v.startsWith('http')) {
      return _bareId.hasMatch(v) && !v.contains('.') ? v : null;
    }
    final uri = Uri.tryParse(v);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final isDrive = host == 'drive.google.com' ||
        host == 'docs.google.com' ||
        host.endsWith('googleusercontent.com');
    if (!isDrive) return null;
    final q = uri.queryParameters['id'];
    if (q != null && _bareId.hasMatch(q)) return q;
    final m = RegExp(r'/(?:file/d|d)/([A-Za-z0-9_-]{10,})').firstMatch(uri.path);
    return m?.group(1);
  }

  /// ดึงรูปจาก Drive เป็น bytes (มี cache และกันโหลดซ้ำพร้อมกัน)
  /// thumb=true ใช้รูปย่อ (รายการ/การ์ด) / thumb=false ใช้ไฟล์ต้นฉบับ (ดูเต็ม)
  Future<Uint8List> fetchPhoto(String urlOrId, {bool thumb = true}) {
    final id = extractDriveId(urlOrId);
    if (id == null) {
      return Future.error(const SheetsException(
        'ไม่ใช่ลิงก์รูปของ Drive',
        code: 'bad_request',
      ));
    }
    final key = '$id|${thumb ? 't' : 'f'}';
    final cached = _photoCache[key];
    if (cached != null) return Future.value(cached);
    final running = _photoInflight[key];
    if (running != null) return running;

    final f = _loadPhoto(id, thumb).then((bytes) {
      _photoCache[key] = bytes;
      return bytes;
    }).whenComplete(() => _photoInflight.remove(key));
    return _photoInflight[key] = f;
  }

  Future<Uint8List> _loadPhoto(String id, bool thumb) async {
    // จำกัดจำนวนที่โหลดพร้อมกัน (Apps Script ตอบช้า)
    while (_photoActive >= _maxPhotoConcurrency) {
      final c = Completer<void>();
      _photoWaiters.add(c);
      await c.future;
    }
    _photoActive++;
    try {
      final d = await _call(
        {'op': 'get_photo', 'fileId': id, 'thumb': thumb},
        retryOnNetworkError: true,
        timeout: const Duration(seconds: 90),
      );
      final b64 = (d is Map) ? d['data'] : null;
      if (b64 is! String || b64.isEmpty) {
        throw const SheetsException(
          'เซิร์ฟเวอร์ไม่ส่งข้อมูลรูปกลับมา',
          code: 'bad_response',
        );
      }
      return base64Decode(b64);
    } finally {
      _photoActive--;
      if (_photoWaiters.isNotEmpty) _photoWaiters.removeAt(0).complete();
    }
  }

  /// เปลี่ยนรหัสผ่าน โดยให้เซิร์ฟเวอร์ตรวจรหัสเดิมเอง
  /// เซิร์ฟเวอร์อ่าน employee_id / current / next จากระดับบนสุดของคำสั่ง (ตรวจกับ Code.gs แล้ว)
  /// error code ที่เป็นไปได้: invalid_password, weak_password (สั้นกว่า 4 ตัว), not_found
  Future<void> changePassword({
    required String employeeId,
    required String oldPassword,
    required String newPassword,
  }) async {
    await _call({
      'op': 'change_password',
      'employee_id': employeeId,
      'current': oldPassword,
      'next': newPassword,
    });
  }

  // ----------------------------------------------------------
  // ส่วนกลางที่ใช้ส่งคำสั่งไปหาเซิร์ฟเวอร์
  // ----------------------------------------------------------

  /// ส่งคำสั่ง แล้วคืนค่าในช่อง "data" ของคำตอบ (หรือโยน SheetsException)
  Future<dynamic> _call(
    Map<String, dynamic> payload, {
    bool retryOnNetworkError = false,
    Duration? timeout,
  }) async {
    final body = jsonEncode(
      {'key': apiKey, ...payload},
      toEncodable: _encodeUnknown,
    );
    final t = timeout ?? this.timeout;

    Map<String, dynamic> json;
    try {
      json = await _postAndParse(body, t);
    } on SheetsException catch (e) {
      // ลองใหม่อีกครั้งเฉพาะคำสั่งอ่านข้อมูล (ห้ามลองซ้ำคำสั่งเขียน เพราะอาจซ้ำ)
      if (retryOnNetworkError && e.code == 'network') {
        json = await _postAndParse(body, t);
      } else {
        rethrow;
      }
    }

    final err = json['error'];
    if (err != null && err != false) {
      throw _toException(json);
    }
    return json.containsKey('data') ? json['data'] : json;
  }

  Future<Map<String, dynamic>> _postAndParse(String body, Duration t) async {
    final text = await _postRaw(body, t);
    return _decode(text);
  }

  Future<String> _postRaw(String body, Duration t) async {
    try {
      final uri = Uri.parse(url);
      var res = await _http
          .post(
            uri,
            headers: const {'Content-Type': 'text/plain; charset=utf-8'},
            body: body,
          )
          .timeout(t);

      // Apps Script ตอบ POST ด้วย 302 -> ตามไปที่ Location ด้วย GET (ห้าม POST ซ้ำ)
      var hops = 0;
      var current = uri;
      while (res.statusCode >= 300 && res.statusCode < 400 && hops < 5) {
        final loc = res.headers['location'];
        if (loc == null || loc.isEmpty) break;
        current = current.resolve(loc);
        res = await _http.get(current).timeout(t);
        hops++;
      }

      if (res.statusCode != 200) {
        throw SheetsException(
          'เซิร์ฟเวอร์ตอบกลับ HTTP ${res.statusCode}',
          code: 'http_${res.statusCode}',
        );
      }
      return utf8.decode(res.bodyBytes);
    } on SheetsException {
      rethrow;
    } catch (e) {
      throw SheetsException(
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่ ($e)',
        code: 'network',
      );
    }
  }

  Map<String, dynamic> _decode(String text) {
    final trimmed = text.trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw SheetsException(
        'เซิร์ฟเวอร์ตอบกลับไม่ใช่ JSON (ตรวจว่า Deploy เป็น Anyone และใช้ URL ที่ลงท้ายด้วย /exec)',
        code: 'bad_response',
        details: trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed,
      );
    }
    if (decoded is! Map) {
      throw const SheetsException(
        'รูปแบบคำตอบจากเซิร์ฟเวอร์ไม่ถูกต้อง',
        code: 'bad_response',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  SheetsException _toException(Map<String, dynamic> json) {
    final err = json['error'];
    String message;
    String? code;
    String? details;
    String? hint;

    if (err is Map) {
      message = (err['message'] ?? err['error'] ?? err.toString()).toString();
      code = err['code']?.toString();
      details = err['details']?.toString();
      hint = err['hint']?.toString();
    } else {
      message = err.toString();
    }
    code ??= json['code']?.toString();
    code ??= RegExp(r'\b\d{5}\b').firstMatch(message)?.group(0);

    return SheetsException(message, code: code, details: details, hint: hint);
  }

  static Object? _encodeUnknown(dynamic o) {
    if (o is DateTime) return o.toIso8601String();
    if (o is Uint8List) return base64Encode(o);
    return o.toString();
  }
}

// ============================================================
// Query builder  (from('table').select()/insert()/update()/upsert()/delete())
// ============================================================

class SheetsQueryBuilder {
  SheetsQueryBuilder._(this._client, this._table);

  final SheetsClient _client;
  final String _table;

  SheetsFilterBuilder select([String columns = '*']) =>
      SheetsFilterBuilder._(_client, _table, 'select', select: columns);

  /// values เป็น Map (แถวเดียว) หรือ List<Map> (หลายแถว)
  SheetsFilterBuilder insert(Object values) =>
      SheetsFilterBuilder._(_client, _table, 'insert', values: values);

  SheetsFilterBuilder update(Map<String, dynamic> values) =>
      SheetsFilterBuilder._(_client, _table, 'update', values: values);

  SheetsFilterBuilder upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  }) =>
      SheetsFilterBuilder._(
        _client,
        _table,
        'upsert',
        values: values,
        onConflict: onConflict,
      );

  SheetsFilterBuilder delete() =>
      SheetsFilterBuilder._(_client, _table, 'delete');
}

enum _Mode { list, single, maybeSingle }

/// ตัวต่อเงื่อนไข และ await ได้ในตัวเอง (เหมือน builder ของ Supabase)
class SheetsFilterBuilder implements Future<dynamic> {
  SheetsFilterBuilder._(
    this._client,
    this._table,
    this._op, {
    this.values,
    this.onConflict,
    String? select,
  }) : _select = select;

  final SheetsClient _client;
  final String _table;
  final String _op;
  final Object? values;
  final String? onConflict;

  /// ถ้าไม่ใช่ null คือขอให้คืนแถวกลับมา (select ปกติ หรือ insert/update ... .select())
  String? _select;

  final List<Map<String, dynamic>> _filters = [];
  final List<String> _or = [];
  final List<Map<String, dynamic>> _order = [];
  int? _limit;
  _Mode _mode = _Mode.list;
  Future<dynamic>? _future;

  // ---------------- ตัวกรอง ----------------

  SheetsFilterBuilder _add(String col, String op, dynamic val,
      {bool negate = false}) {
    final f = <String, dynamic>{'c': col, 'o': op, 'v': val};
    if (negate) f['n'] = true;
    _filters.add(f);
    return this;
  }

  SheetsFilterBuilder eq(String column, Object? value) =>
      _add(column, 'eq', value);
  SheetsFilterBuilder neq(String column, Object? value) =>
      _add(column, 'neq', value);
  SheetsFilterBuilder gt(String column, Object? value) =>
      _add(column, 'gt', value);
  SheetsFilterBuilder gte(String column, Object? value) =>
      _add(column, 'gte', value);
  SheetsFilterBuilder lt(String column, Object? value) =>
      _add(column, 'lt', value);
  SheetsFilterBuilder lte(String column, Object? value) =>
      _add(column, 'lte', value);
  SheetsFilterBuilder like(String column, String pattern) =>
      _add(column, 'like', pattern);
  SheetsFilterBuilder ilike(String column, String pattern) =>
      _add(column, 'ilike', pattern);

  /// เทียบกับ Supabase: .isFilter('col', null)
  SheetsFilterBuilder isFilter(String column, Object? value) =>
      _add(column, 'is', value);

  /// เทียบกับ Supabase: .inFilter('col', [..])
  SheetsFilterBuilder inFilter(String column, List<dynamic> values) =>
      _add(column, 'in', values);

  /// .not('col', 'eq', value)
  SheetsFilterBuilder not(String column, String operator, Object? value) =>
      _add(column, operator, _normalize(operator, value), negate: true);

  /// .or('a.ilike.%x%,b.eq.y')
  SheetsFilterBuilder or(String filters, {String? referencedTable}) {
    _or.add(filters);
    return this;
  }

  /// .filter('col', 'is', null)
  SheetsFilterBuilder filter(String column, String operator, Object? value) =>
      _add(column, operator, _normalize(operator, value));

  /// .match({'a': 1, 'b': 2})
  SheetsFilterBuilder match(Map<String, Object?> query) {
    query.forEach((k, v) => _add(k, 'eq', v));
    return this;
  }

  /// ถ้า operator เป็น in และค่าเป็นข้อความแบบ "(a,b)" ให้แปลงเป็น List
  static dynamic _normalize(String op, Object? value) {
    if (op == 'in' && value is String) {
      var s = value.trim();
      if (s.startsWith('(') && s.endsWith(')')) {
        s = s.substring(1, s.length - 1);
      }
      return s.isEmpty ? <String>[] : s.split(',').map((e) => e.trim()).toList();
    }
    return value;
  }

  // ---------------- ตัวปรับผลลัพธ์ ----------------

  /// ใน Supabase ค่าเริ่มต้นของ ascending คือ false (ใหม่ -> เก่า)
  SheetsFilterBuilder order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
    String? foreignTable,
  }) {
    _order.add({'c': column, 'a': ascending});
    return this;
  }

  SheetsFilterBuilder limit(int count, {String? referencedTable}) {
    _limit = count;
    return this;
  }

  /// ใช้กับ insert/update/upsert/delete เพื่อขอแถวกลับมา (หรือเปลี่ยนคอลัมน์ของ select)
  SheetsFilterBuilder select([String columns = '*']) {
    _select = columns;
    return this;
  }

  /// ต้องได้ 1 แถวพอดี ไม่งั้นโยน SheetsException (code: PGRST116)
  SheetsFilterBuilder single() {
    _mode = _Mode.single;
    return this;
  }

  /// ได้ 0 แถว -> null, 1 แถว -> Map, มากกว่า 1 -> โยน SheetsException
  SheetsFilterBuilder maybeSingle() {
    _mode = _Mode.maybeSingle;
    return this;
  }

  // ---------------- ส่งคำสั่งจริง ----------------

  Future<dynamic> _execute() => _future ??= _run();

  Future<dynamic> _run() async {
    final payload = <String, dynamic>{'op': _op, 'table': _table};
    if (_select != null) payload['select'] = _select;
    if (_filters.isNotEmpty) payload['filters'] = _filters;
    if (_or.isNotEmpty) payload['or'] = _or;
    if (_order.isNotEmpty) payload['order'] = _order;

    var lim = _limit;
    if (_op == 'select' && _mode != _Mode.list) {
      // ขอแค่ 2 แถวพอ เพื่อตรวจว่าซ้ำหรือไม่
      lim = (lim == null || lim > 2) ? 2 : lim;
    }
    if (_op == 'select' && lim != null) payload['limit'] = lim;

    if (values != null) payload['values'] = values;
    if (onConflict != null) payload['onConflict'] = onConflict;

    final data = await _client._call(
      payload,
      retryOnNetworkError: false,
    );

    // insert/update/delete ที่ไม่ได้เรียก .select() -> Supabase คืน null
    if (_op != 'select' && _select == null) return null;

    final List raw = data is List ? data : (data == null ? const [] : [data]);
    final rows = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);

    switch (_mode) {
      case _Mode.list:
        return rows;
      case _Mode.single:
        if (rows.length != 1) {
          throw SheetsException(
            'JSON object requested, multiple (or no) rows returned',
            code: 'PGRST116',
            details: 'The result contains ${rows.length} rows',
          );
        }
        return rows.first;
      case _Mode.maybeSingle:
        if (rows.isEmpty) return null;
        if (rows.length > 1) {
          throw SheetsException(
            'JSON object requested, multiple (or no) rows returned',
            code: 'PGRST116',
            details: 'The result contains ${rows.length} rows',
          );
        }
        return rows.first;
    }
  }

  // ---------------- ทำให้ await ได้ (implements Future) ----------------

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue,
          {Function? onError}) =>
      _execute().then(onValue, onError: onError);

  @override
  Future<dynamic> catchError(Function onError,
          {bool Function(Object error)? test}) =>
      _execute().catchError(onError, test: test);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _execute().whenComplete(action);

  @override
  Stream<dynamic> asStream() => _execute().asStream();

  @override
  Future<dynamic> timeout(Duration timeLimit,
          {FutureOr<dynamic> Function()? onTimeout}) =>
      _execute().timeout(timeLimit, onTimeout: onTimeout);
}

// ============================================================
// Storage  (storage.from('attendance').upload / uploadBinary / getPublicUrl)
// ============================================================

class SheetsStorage {
  SheetsStorage._(this._client);
  final SheetsClient _client;

  SheetsBucket from(String bucket) => SheetsBucket._(_client, bucket);
}

class SheetsBucket {
  SheetsBucket._(this._client, this.bucket);
  final SheetsClient _client;
  final String bucket;

  /// มือถือ: รับ File (dart:io) หรือ XFile / Uint8List ก็ได้
  /// คืน "URL ของรูป" (ต่างจาก Supabase ที่คืนชื่อไฟล์) ให้เก็บลงคอลัมน์รูปได้เลย
  Future<String> upload(String path, dynamic file, {dynamic fileOptions}) async {
    final bytes = await _readBytes(file);
    return _uploadBytes(path, bytes);
  }

  /// เว็บ: รับ Uint8List
  Future<String> uploadBinary(String path, Uint8List data,
      {dynamic fileOptions}) {
    return _uploadBytes(path, data);
  }

  /// ซิงโครนัสเหมือนเดิม: ถ้า path เป็น URL อยู่แล้วคืนตามนั้น
  /// ถ้าเป็นชื่อไฟล์ที่เพิ่งอัปโหลดในรอบนี้ คืน URL ที่จำไว้ ไม่งั้นคืนข้อความว่าง
  String getPublicUrl(String path) {
    if (path.startsWith('http')) return path;
    return _client._uploadedUrls[path] ?? '';
  }

  Future<String> _uploadBytes(String path, Uint8List bytes) async {
    // เซิร์ฟเวอร์อ่าน path / base64 / contentType จากระดับบนสุดของคำสั่ง
    // และตอบกลับเป็น {path, url} (ตรวจกับ Code.gs แล้ว) ไม่มีฟิลด์ bucket
    final data = await _client._call(
      {
        'op': 'upload',
        'path': path,
        'contentType': _guessMime(path),
        'base64': base64Encode(bytes),
      },
      timeout: const Duration(seconds: 120),
    );

    String? url;
    if (data is String) {
      url = data;
    } else if (data is Map) {
      url = (data['url'] ?? data['publicUrl'] ?? data['public_url'])
          ?.toString();
    }
    if (url == null || url.isEmpty) {
      throw const SheetsException(
        'อัปโหลดสำเร็จแต่เซิร์ฟเวอร์ไม่ส่ง URL ของรูปกลับมา',
        code: 'bad_response',
      );
    }
    _client._uploadedUrls[path] = url;
    return url;
  }

  static Future<Uint8List> _readBytes(dynamic file) async {
    if (file is Uint8List) return file;
    if (file is List<int>) return Uint8List.fromList(file);
    // dart:io File และ XFile ต่างก็มี readAsBytes()
    final bytes = await (file as dynamic).readAsBytes();
    return bytes is Uint8List ? bytes : Uint8List.fromList(List<int>.from(bytes));
  }

  static String _guessMime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

// ============================================================
// Functions  (functions.invoke('push-notify', body: {...}))
// ============================================================

class SheetsFunctionResponse {
  const SheetsFunctionResponse(this.status, this.data);
  final int status;
  final dynamic data;
}

class SheetsFunctions {
  SheetsFunctions._(this._client);
  final SheetsClient _client;

  Future<SheetsFunctionResponse> invoke(
    String functionName, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    switch (functionName) {
      case 'push-notify':
        {
          // เซิร์ฟเวอร์อ่าน title / body จากระดับบนสุดของคำสั่ง (ตรวจกับ Code.gs แล้ว)
          final data = await _client._call({
            'op': 'notify',
            'title': body?['title'],
            'body': body?['body'],
          });
          return SheetsFunctionResponse(200, data);
        }
      default:
        throw SheetsException(
          'ยังไม่รองรับ function "$functionName"',
          code: 'unsupported',
        );
    }
  }
}
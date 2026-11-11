// lib/widgets/drive_image.dart
//
// แสดงรูปจาก Google Drive ผ่าน SheetsClient.fetchPhoto (base64 -> Image.memory)
// ใช้ได้ทั้งเว็บและมือถือ ไม่ติด CORS
// ถ้า url ไม่ใช่ลิงก์ Drive (เช่น Supabase) จะใช้ Image.network ตามเดิม

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:employee_attendance_app/services/sheets_client.dart';

class DriveImage extends StatefulWidget {
  const DriveImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.thumb = true,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// true = รูปย่อ (รายการ/การ์ด/avatar), false = ไฟล์ต้นฉบับ (หน้าดูรูปเต็ม)
  final bool thumb;

  @override
  State<DriveImage> createState() => _DriveImageState();
}

class _DriveImageState extends State<DriveImage> {
  Future<Uint8List>? _future;

  bool get _isDrive => SheetsClient.isDrivePhoto(widget.url);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DriveImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.thumb != widget.thumb) _load();
  }

  void _load() {
    _future = _isDrive
        ? SheetsClient.instance.fetchPhoto(widget.url, thumb: widget.thumb)
        : null;
  }

  Widget _box(Widget child) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(child: child),
      );

  Widget _broken() => _box(const Icon(Icons.broken_image, color: Colors.grey));

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) return _broken();

    if (!_isDrive) {
      return Image.network(
        widget.url,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (_, __, ___) => _broken(),
      );
    }

    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return _broken();
        final bytes = snap.data;
        if (bytes == null) {
          return _box(const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _broken(),
        );
      },
    );
  }
}

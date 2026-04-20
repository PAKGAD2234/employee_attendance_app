import 'package:flutter/material.dart';

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late String _currentTime;
  late String _currentDate;

  @override
  void initState() {
    super.initState();
    _updateTime();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(_updateTime);
      return true;
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    _currentTime = '$h:$m:$s';

    const thDays = ['จันทร์','อังคาร','พุธ','พฤหัส','ศุกร์','เสาร์','อาทิตย์'];
    const thMonths = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                      'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
    _currentDate =
        'วัน${thDays[now.weekday - 1]}ที่ ${now.day} '
        '${thMonths[now.month - 1]} ${now.year + 543}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
      ),
      child: Column(
        children: [
          Text(
            _currentTime,
            style: const TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentDate,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.55),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
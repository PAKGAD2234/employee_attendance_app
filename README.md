<div align="center">

# 📱 Employee Attendance App

แอปพลิเคชันบันทึกเวลาเข้า-ออกพนักงาน รองรับการใช้งานทั้งฝั่งพนักงานและแอดมิน
🎯 โปรเจกต์นี้ถูกออกแบบเพื่อใช้งานจริงในบริษัท

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=flat&logo=supabase&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)

</div>

---

## ✨ Features

| Feature | Description |
|---|---|
| 👤 จัดการพนักงาน | เพิ่ม  |
| ⏰ Check-in / Check-out | บันทึกเวลาเข้า-ออกงาน |
| 📍 GPS Location | บันทึกพิกัดพร้อมกัน |
| 📸 ถ่ายภาพยืนยัน | ยืนยันตัวตนด้วยรูปภาพ |
| 📊 ประวัติการทำงาน | ดูย้อนหลังแบบละเอียด |
| 📅 ปฏิทินสรุป | ภาพรวมการเข้างาน |
| ⚠️ ตรวจสอบการขาด/สาย | แจ้งเตือนอัตโนมัติ (เร็วๆ นี้) |
| 🔐 ระบบ Login | Authentication & Logout |

---

## 🖼️ Screenshots

### 🔐 Auth & Home

| Login | Home | Employee Home |
|:---:|:---:|:---:|
| <img width="260" src="https://github.com/user-attachments/assets/89294902-3a9a-48ba-9ba1-1770bc70d64f" /> | <img width="260" src="https://github.com/user-attachments/assets/76d4ae9d-d767-49d7-a674-5f7d37afa1d3" /> | <img width="260" src="https://github.com/user-attachments/assets/96c00e78-778e-4d53-aade-e335c097f98a" /> |

### ⏰ Attendance

| Check-in | Check-out | History |
|:---:|:---:|:---:|
| <img width="260" src="https://github.com/user-attachments/assets/04b847ac-d720-41b2-8d98-99b1719c48c5" /> | <img width="260" src="https://github.com/user-attachments/assets/0c8bf5c9-0a2a-4a3e-9da0-f6a0638d1969" /> | <img width="260" src="https://github.com/user-attachments/assets/370be9d6-16dd-4307-89b9-45150947a125" /> |

### ⚙️ Admin

| Employee List | Admin Dashboard | Add Employee | Create Username |
|:---:|:---:|:---:|:---:|
| <img width="190" src="https://github.com/user-attachments/assets/69a96aa9-74fc-4756-ba0e-66da28a78dbb" /> | <img width="190" src="https://github.com/user-attachments/assets/c44a6571-587d-4ad0-b552-be69936a2e4d" /> | <img width="190" src="https://github.com/user-attachments/assets/4201978c-cf2a-4d89-aa0b-8e540bfc37f8" /> | <img width="190" src="https://github.com/user-attachments/assets/326e594e-2aaf-4a85-b6fb-a061aa0c071c" /> |



---

## 📂 Project Structure

```bash
lib/
└── view/
    ├── splash_ui.dart
    ├── login_ui.dart
    ├── home_ui.dart
    ├── employee_home_ui.dart
    ├── employee_profile_ui.dart
    ├── employee_history_ui.dart
    ├── checkin_ui.dart
    ├── checkout_ui.dart
    ├── admin_ui.dart
    └── add_employee_ui.dart
```

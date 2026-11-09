// lib/services/sheets_config.dart
//
// ค่าตั้งค่าสำหรับเชื่อมต่อ Google Apps Script
// - ห้ามส่งไฟล์นี้ให้ใคร และอย่าอัปโหลดขึ้น GitHub สาธารณะ
// - API_KEY ที่ฝังในแอปไม่ใช่ความปลอดภัยเต็มรูปแบบ (เทียบเท่า Supabase anon key เดิม)

/// Web app URL ของ Apps Script (ลงท้ายด้วย /exec)
const String kSheetsUrl = 'https://script.google.com/macros/s/AKfycbyGMeX2OFVROh-E5qO4VxEPHvdAesZNmJLCnEsZUqqACHOsGce1DQQy8mpk4NHach636Q/exec';

/// API_KEY เดียวกับที่เก็บใน Script properties
const String kSheetsApiKey = '53f6ddc4253242069816bc98c9b323ca65a35ae59b0a478b9f3922f988293246';

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

const LINE_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN')!
const LINE_GROUP_ID = Deno.env.get('LINE_GROUP_ID')!

async function pushLine(to: string, message: string) {
  await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${LINE_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      to,
      messages: [{ type: 'text', text: message }]
    })
  })
}

function parseAsBangkok(s?: string) {
  if (!s) return null;
  if (/[Zz]|[+\-]\d{2}:\d{2}$/.test(s)) return new Date(s);
  return new Date(s + '+07:00');
}

Deno.serve(async (req) => {
  const payload = await req.json()

  // log ดู payload จริงๆ
  console.log('Full payload:', JSON.stringify(payload))

  const record = payload.record
  const oldRecord = payload.old_record

  console.log('record:', JSON.stringify(record))
  console.log('oldRecord:', JSON.stringify(oldRecord))

  if (!record?.checkin_time) {
    console.log('SKIPPED - no checkin_time in record')
    return new Response('skip', { status: 200 })
  }

  if (oldRecord?.checkin_time) {
    console.log('SKIPPED - checkin_time already existed in old_record')
    return new Response('skip', { status: 200 })
  }

  // ดึงข้อมูลพนักงาน
  const { data: emp, error: empError } = await supabase
    .from('employees')
    .select('full_name, phone, work_site_id')
    .eq('id', record.employee_id)
    .single()

  console.log('emp:', JSON.stringify(emp), 'empError:', JSON.stringify(empError))

  if (!emp) return new Response('employee not found', { status: 200 })

  // ดึงชื่อสาขา
  const { data: site } = await supabase
    .from('work_sites')
    .select('name')
    .eq('id', emp.work_site_id)
    .maybeSingle()

  const checkinTime = parseAsBangkok(record.checkin_time);
  if (!checkinTime) {
    console.log('Invalid checkin_time:', record.checkin_time);
    return new Response('skip', { status: 200 });
  }
  const timeStr = new Intl.DateTimeFormat('th-TH', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'Asia/Bangkok'
  }).format(checkinTime)
  const siteName = site?.name ?? '-'
  const lateTag = record.late ? ' ⚠️ สาย' : ''

  const message = `✅ ${emp.full_name} เช็คอินแล้ว${lateTag}\n⏰ เวลา: ${timeStr} น.\n📍 สาขา: ${siteName}`

  console.log('message:', message)

  // ✅ แจ้ง admin เข้ากลุ่ม LINE กลุ่มเดียว
  await pushLine(LINE_GROUP_ID, message)

  // ดึง LINE recipients (เหลือใช้เฉพาะ owner ตามสาขา)
  const { data: recipients, error: recipientsError } = await supabase
    .from('line_recipients')
    .select('line_user_id, role, work_site_id')
    .eq('role', 'owner')

  console.log('recipients:', JSON.stringify(recipients), 'error:', JSON.stringify(recipientsError))

  for (const r of recipients ?? []) {
    if (r.line_user_id.startsWith('PLACEHOLDER')) continue

    if (r.work_site_id === emp.work_site_id) {
      console.log('pushing to owner:', r.line_user_id)
      await pushLine(r.line_user_id, message)
    }
  }

  return new Response('ok', { status: 200 })
})
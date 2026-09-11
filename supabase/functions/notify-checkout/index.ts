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
  const record = payload.record
  const oldRecord = payload.old_record

  // ต้องมี checkout_time และเพิ่งถูก set ครั้งแรก
  if (!record?.checkout_time || oldRecord?.checkout_time) {
    return new Response('skip', { status: 200 })
  }

  const { data: emp } = await supabase
    .from('employees')
    .select('full_name, work_site_id')
    .eq('id', record.employee_id)
    .single()

  if (!emp) return new Response('employee not found', { status: 200 })

  const { data: site } = await supabase
    .from('work_sites')
    .select('name')
    .eq('id', emp.work_site_id)
    .maybeSingle()

  // แปลงเวลาเป็น timezone ไทย
  const checkoutTime = parseAsBangkok(record.checkout_time);
  if (!checkoutTime) {
    console.log('Invalid checkout_time:', record.checkout_time);
    return new Response('skip', { status: 200 });
  }
  const timeStr = new Intl.DateTimeFormat('th-TH', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'Asia/Bangkok'
  }).format(checkoutTime)
  const siteName = site?.name ?? '-'

  const message = `🔚 ${emp.full_name} เช็คเอาท์แล้ว\n⏰ เวลา: ${timeStr} น.\n📍 สาขา: ${siteName}`

  // ✅ แจ้ง admin เข้ากลุ่ม LINE กลุ่มเดียว
  await pushLine(LINE_GROUP_ID, message)

  // เหลือใช้เฉพาะ owner ตามสาขา
  const { data: recipients } = await supabase
    .from('line_recipients')
    .select('line_user_id, role, work_site_id')
    .eq('role', 'owner')

  for (const r of recipients ?? []) {
    if (r.line_user_id.startsWith('PLACEHOLDER')) continue

    if (r.work_site_id === emp.work_site_id) {
      await pushLine(r.line_user_id, message)
    }
  }

  return new Response('ok', { status: 200 })
})
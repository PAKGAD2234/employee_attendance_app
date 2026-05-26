import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

const LINE_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN')!

async function pushLine(userId: string, message: string) {
  await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${LINE_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      to: userId,
      messages: [{ type: 'text', text: message }]
    })
  })
}

Deno.serve(async (req) => {
  const payload = await req.json()
  const record = payload.record // ข้อมูลจาก attendance ที่เพิ่งถูก INSERT

  // ดึงข้อมูลพนักงาน
  const { data: emp } = await supabase
    .from('employees')
    .select('full_name, phone, work_site_id')
    .eq('id', record.employee_id)
    .single()

  if (!emp) return new Response('employee not found', { status: 200 })

  // ดึงชื่อสาขา
  const { data: site } = await supabase
    .from('work_sites')
    .select('name')
    .eq('id', emp.work_site_id)
    .maybeSingle()

  const checkinTime = new Date(record.checkin_time)
  const timeStr = `${String(checkinTime.getHours()).padStart(2,'0')}:${String(checkinTime.getMinutes()).padStart(2,'0')}`
  const isLate = record.late === true
  const siteName = site?.name ?? '-'

  const message = isLate
    ? `⚠️ ${emp.full_name} เช็คอินสาย!\n⏰ เวลา: ${timeStr} น.\n📍 สาขา: ${siteName}`
    : `✅ ${emp.full_name} เช็คอินแล้ว\n⏰ เวลา: ${timeStr} น.\n📍 สาขา: ${siteName}`

  // ดึง LINE user_id ของ Admin และเจ้าของทุกคน
  const { data: recipients } = await supabase
    .from('line_recipients')
    .select('line_user_id')

  if (!recipients) return new Response('no recipients', { status: 200 })

  // ส่งให้ทุกคนใน line_recipients
  for (const r of recipients) {
    if (r.line_user_id.startsWith('PLACEHOLDER')) continue
    await pushLine(r.line_user_id, message)
  }

  return new Response('ok', { status: 200 })
})
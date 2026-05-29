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
  const record = payload.record

  // ดึงข้อมูลพนักงาน
  const { data: emp } = await supabase
    .from('employees')
    .select('full_name, work_site_id')
    .eq('id', record.employee_id)
    .single()

  if (!emp) return new Response('employee not found', { status: 200 })

  // ดึงชื่อสาขา
  const { data: site } = await supabase
    .from('work_sites')
    .select('name')
    .eq('id', emp.work_site_id)
    .maybeSingle()

  const checkoutTime = new Date(record.checkout_time)
  const timeStr = `${String(checkoutTime.getHours()).padStart(2,'0')}:${String(checkoutTime.getMinutes()).padStart(2,'0')}`
  const siteName = site?.name ?? '-'

  const message = `🔚 ${emp.full_name} เช็คเอาท์แล้ว\n⏰ เวลา: ${timeStr} น.\n📍 สาขา: ${siteName}`

  // ดึง LINE user_id ของ Admin ทุกคน
  const { data: recipients } = await supabase
    .from('line_recipients')
    .select('line_user_id')

  if (!recipients) return new Response('no recipients', { status: 200 })

  for (const r of recipients) {
    if (r.line_user_id.startsWith('PLACEHOLDER')) continue
    await pushLine(r.line_user_id, message)
  }

  return new Response('ok', { status: 200 })
})
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const LINE_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN')

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !LINE_TOKEN) {
  throw new Error(
    'Missing required environment variables: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, LINE_CHANNEL_ACCESS_TOKEN'
  )
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

async function replyLine(replyToken: string, message: string) {
  await fetch('https://api.line.me/v2/bot/message/reply', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${LINE_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      replyToken,
      messages: [{ type: 'text', text: message }]
    })
  })
}

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
  const body = await req.json()
  const event = body.events?.[0]
  console.log('LINE user_id:', event?.source?.userId)
  if (!event) return new Response('ok', { status: 200 })

  // พนักงานกดปุ่มยืนยัน
  if (event.type === 'postback') {
    const data = event.postback.data as string
    // data format: "confirm_arrival|employee_id|work_date"
    const [action, employeeId, workDate] = data.split('|')

    if (action === 'confirm_arrival') {
      // บันทึกลง attendance ว่ายืนยันแล้ว
      const { data: existing } = await supabase
        .from('attendance')
        .select('id')
        .eq('employee_id', employeeId)
        .eq('work_date', workDate)
        .maybeSingle()

      if (existing) {
        // มี record อยู่แล้ว update confirmed
        await supabase
          .from('attendance')
          .update({
            confirmed_arrival: true,
            confirmed_at: new Date().toISOString()
          })
          .eq('id', existing.id)
      } else {
        // ยังไม่มี record สร้างใหม่
        await supabase
          .from('attendance')
          .insert({
            employee_id: employeeId,
            work_date: workDate,
            confirmed_arrival: true,
            confirmed_at: new Date().toISOString()
          })
      }

      // ดึงชื่อพนักงาน
      const { data: emp } = await supabase
        .from('employees')
        .select('full_name')
        .eq('id', employeeId)
        .maybeSingle()

      const employeeName = emp?.full_name ?? ''

      // ตอบกลับพนักงาน
      await replyLine(
        event.replyToken,
        `✅ รับทราบแล้วครับ ${employeeName}\nไปทำงานให้สนุกนะครับ! 💪\n\n📲 อย่าลืมเช็คอินด้วยนะครับ\nhttps://timetrack.opmatch.com`
      )

      // แจ้ง Admin ว่าพนักงานยืนยันแล้ว
      const { data: recipients } = await supabase
        .from('line_recipients')
        .select('line_user_id')

      for (const r of recipients ?? []) {
        if (r.line_user_id.startsWith('PLACEHOLDER')) continue
        await pushLine(
          r.line_user_id,
          `📋 ${emp?.full_name ?? 'พนักงาน'} ยืนยันว่าจะมาทำงานแล้ว\n📅 วันที่: ${workDate}`
        )
      }
    }
  }

  return new Response('ok', { status: 200 })
})
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const LINE_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN')!

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
  if (!event) return new Response('ok', { status: 200 })

  console.log('LINE event type:', event.type)
  console.log('LINE user_id:', event?.source?.userId)

  if (event.type === 'postback') {
    const data = event.postback.data as string
    const [action, employeeId, workDate] = data.split('|')

    if (action === 'confirm_arrival') {
      const { data: emp } = await supabase
        .from('employees')
        .select('full_name')
        .eq('id', employeeId)
        .maybeSingle()

      const employeeName = emp?.full_name ?? 'พนักงาน'

      // ✅ upsert confirmed_arrival = true
      await supabase
        .from('attendance')
        .upsert({
          employee_id: employeeId,
          work_date: workDate,
          confirmed_arrival: true,
          confirmed_at: new Date().toISOString()
        }, {
          onConflict: 'employee_id,work_date',
          ignoreDuplicates: false
        })

      await replyLine(
        event.replyToken,
        `✅ รับทราบแล้วครับ ${employeeName}\nไปทำงานให้สนุกนะครับ! 💪\n\n📲 อย่าลืมเช็คอินด้วยนะครับ\nhttps://timetrack.opmatch.com`
      )

      // แจ้ง Admin ทุกคน (role = admin ไม่ filter สาขา)
      const { data: recipients } = await supabase
        .from('line_recipients')
        .select('line_user_id')
        .eq('role', 'admin')

      for (const r of recipients ?? []) {
        if (r.line_user_id.startsWith('PLACEHOLDER')) continue
        await pushLine(r.line_user_id,
          `📋 ${employeeName} ยืนยันว่าจะมาทำงานแล้ว\n📅 วันที่: ${workDate}`
        )
      }
    }
  }

  return new Response('ok', { status: 200 })
})
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const LINE_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN')!
const LINE_GROUP_ID = Deno.env.get('LINE_GROUP_ID')!

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

Deno.serve(async (req) => {
  const body = await req.json()
  const event = body.events?.[0]
  if (!event) return new Response('ok', { status: 200 })

  console.log('LINE event type:', event.type)
  console.log('LINE user_id:', event?.source?.userId)
  console.log('LINE group_id:', event?.source?.groupId)

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

      // ✅ บันทึกสถานะยืนยันว่าจะมาทำงานลงตาราง attendance
      await supabase.from('attendance').upsert({
        employee_id: employeeId,
        work_date: workDate,
        confirmed_arrival: true
      }, { onConflict: 'employee_id,work_date' })

      await replyLine(
        event.replyToken,
        `✅ รับทราบแล้วครับ ${employeeName}\nไปทำงานให้สนุกนะครับ! 💪\n\n📲 อย่าลืมเช็คอินด้วยนะครับ\nhttps://timetrack.opmatch.com`
      )

      // ✅ แจ้งเข้ากลุ่ม LINE กลุ่มเดียว แทนการ loop ส่งหา admin ทีละคน
      await pushLine(
        LINE_GROUP_ID,
        `📋 ${employeeName} ยืนยันว่าจะมาทำงานแล้ว\n📅 วันที่: ${workDate}`
      )
    }
  }

  return new Response('ok', { status: 200 })
})
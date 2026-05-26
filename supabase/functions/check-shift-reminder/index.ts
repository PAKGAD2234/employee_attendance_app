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

async function getRecipients() {
  const { data } = await supabase
    .from('line_recipients')
    .select('line_user_id')
  return (data ?? []).filter(r => !r.line_user_id.startsWith('PLACEHOLDER'))
}

Deno.serve(async () => {
  const now = new Date(new Date().getTime() + 7 * 60 * 60 * 1000)
  const todayStr = now.toISOString().split('T')[0]
  const todayDay = now.getDay()

  const nowMinutes = now.getHours() * 60 + now.getMinutes()
  const currentHHMM = `${String(now.getHours()).padStart(2,'0')}:${String(now.getMinutes()).padStart(2,'0')}`

  console.log('เวลาไทย:', now.toISOString())
  console.log('currentHHMM:', currentHHMM)
  console.log('nowMinutes:', nowMinutes)

  const { data: schedules } = await supabase
    .from('employee_weekly_schedules')
    .select(`
      employee_id,
      employees ( id, full_name, line_user_id, phone ),
      shift_templates ( start_time, name )
    `)
    .eq('day_of_week', todayDay)
    .or(`effective_until.is.null,effective_until.gte.${todayStr}`)

  const { data: overrides } = await supabase
    .from('schedule_overrides')
    .select(`
      employee_id,
      custom_start_time,
      employees ( id, full_name, line_user_id, phone ),
      shift_templates ( start_time, name )
    `)
    .eq('override_date', todayStr)
    .neq('override_type', 'leave')

  const allSchedules = [
    ...(schedules ?? []).map(s => ({
      emp: s.employees as any,
      shiftStart: s.shift_templates?.start_time?.substring(0, 5)
    })),
    ...(overrides ?? []).map(o => ({
      emp: o.employees as any,
      shiftStart: (o.custom_start_time as string)?.substring(0, 5)
                ?? (o.shift_templates as any)?.start_time?.substring(0, 5)
    }))
  ].filter(s => s.emp && s.shiftStart)

  const seen = new Set<string>()
  const uniqueSchedules = allSchedules.filter(s => {
    const key = `${s.emp.id}-${s.shiftStart}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })

  console.log('schedules จาก DB:', schedules?.length ?? 0)
  console.log('allSchedules:', JSON.stringify(uniqueSchedules))

  if (uniqueSchedules.length === 0) {
    return new Response('no schedules', { status: 200 })
  }

  const recipients = await getRecipients()

  for (const { emp, shiftStart } of uniqueSchedules) {
    if (!shiftStart || !emp) continue

    const shiftMinutes = parseInt(shiftStart.split(':')[0]) * 60 + parseInt(shiftStart.split(':')[1])
    const diffFromNow = (shiftMinutes - nowMinutes + 24 * 60) % (24 * 60)

    console.log(`${emp.full_name} shiftStart:${shiftStart} diffFromNow:${diffFromNow}`)

    if (diffFromNow === 30 && emp.line_user_id) {
      const flexMessage = {
        to: emp.line_user_id,
        messages: [{
          type: 'flex',
          altText: 'เตือนเข้างาน',
          contents: {
            type: 'bubble',
            header: {
              type: 'box',
              layout: 'vertical',
              backgroundColor: '#185FA5',
              contents: [{
                type: 'text',
                text: 'เตือนเข้างาน',
                color: '#ffffff',
                weight: 'bold',
                size: 'lg'
              }]
            },
            body: {
              type: 'box',
              layout: 'vertical',
              spacing: 'sm',
              contents: [
                { type: 'text', text: `สวัสดี ${emp.full_name}`, weight: 'bold' },
                { type: 'text', text: `กะงานเริ่ม ${shiftStart} น. (อีก 30 นาที)`, color: '#555555' }
              ]
            },
            footer: {
              type: 'box',
              layout: 'vertical',
              contents: [{
                type: 'button',
                style: 'primary',
                color: '#1D9E75',
                action: {
                  type: 'postback',
                  label: 'ยืนยันเข้างาน',
                  data: `confirm_arrival|${emp.id}|${todayStr}`,
                  displayText: 'ยืนยันเข้างานแล้วครับ'
                }
              }]
            }
          }
        }]
      }

      const res = await fetch('https://api.line.me/v2/bot/message/push', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${LINE_TOKEN}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(flexMessage)
      })
      const resBody = await res.json()
      console.log('LINE response:', JSON.stringify(resBody))
    }

    if (diffFromNow === 0 ) {
      const { data: attendance } = await supabase
        .from('attendance')
        .select('id, checkin_time, confirmed_arrival')
        .eq('employee_id', emp.id)
        .eq('work_date', todayStr)
        .maybeSingle()

      if (attendance?.checkin_time) continue

      const confirmed = attendance?.confirmed_arrival === true
      const alertMsg = confirmed
        ? `⚠️ ${emp.full_name} กดยืนยันว่าจะมาแล้ว แต่ยังไม่เช็คอิน!\n⏰ กะงาน: ${shiftStart} น.\n📞 ${emp.phone ?? 'ไม่มีเบอร์'}`
        : `🚨 ${emp.full_name} ไม่ตอบสนองและไม่เช็คอิน!\n⏰ กะงาน: ${shiftStart} น.\n📞 ${emp.phone ?? 'ไม่มีเบอร์'}\nโทรหาได้เลย!`

      for (const r of recipients) {
        await pushLine(r.line_user_id, alertMsg)
      }
    }
  }

  return new Response('done', { status: 200 })
})
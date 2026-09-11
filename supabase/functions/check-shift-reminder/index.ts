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

Deno.serve(async () => {
  const now = new Date(new Date().getTime() + 7 * 60 * 60 * 1000)
  const todayStr = now.toISOString().split('T')[0]
  const todayDay = now.getDay()
  const nowMinutes = now.getHours() * 60 + now.getMinutes()

  console.log('เวลาไทย:', now.toISOString())
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

  console.log('uniqueSchedules:', JSON.stringify(uniqueSchedules))

  if (uniqueSchedules.length === 0) {
    return new Response('no schedules', { status: 200 })
  }

  for (const { emp, shiftStart } of uniqueSchedules) {
    if (!shiftStart || !emp) continue

    const shiftMinutes =
      parseInt(shiftStart.split(':')[0]) * 60 + parseInt(shiftStart.split(':')[1])
    const diffFromNow = (shiftMinutes - nowMinutes + 24 * 60) % (24 * 60)

    console.log(`${emp.full_name} shiftStart:${shiftStart} diffFromNow:${diffFromNow}`)

    // ---- เตือนล่วงหน้า 30 นาที (ส่งข้อความธรรมดา ไม่มีปุ่มยืนยัน) ----
    if (diffFromNow === 30 && emp.line_user_id) {
      await pushLine(
        emp.line_user_id,
        `✅ รับทราบแล้วครับ ${emp.full_name}\nไปทำงานให้สนุกนะครับ! 💪\n\n📲 อย่าลืมเช็คอินด้วยนะครับ\nhttps://timetrack.opmatch.com`
      )
    }

    // ---- ถึงเวลางานแล้ว ยังไม่เช็คอิน → แจ้งเข้ากลุ่ม ----
    if (diffFromNow === 0) {
      const { data: attendance } = await supabase
        .from('attendance')
        .select('id, checkin_time, confirmed_arrival')
        .eq('employee_id', emp.id)
        .eq('work_date', todayStr)
        .maybeSingle()

      // เช็คอินแล้วจริง → ข้ามไป ไม่ต้องแจ้ง
      if (attendance?.checkin_time) continue

      const confirmed = attendance?.confirmed_arrival === true
      const alertMsg = confirmed
        ? `📋 ${emp.full_name} ยืนยันว่าจะมาทำงานแล้ว แต่ยังไม่เช็คอิน!\n⏰ กะงาน: ${shiftStart} น.\n📞 ${emp.phone ?? 'ไม่มีเบอร์'}\nโทรหาได้เลย!`
        : `🚨 ${emp.full_name} ยังไม่เช็คอิน!\n⏰ กะงาน: ${shiftStart} น.\n📞 ${emp.phone ?? 'ไม่มีเบอร์'}\nโทรหาได้เลย!`

      // ✅ ส่งเข้ากลุ่ม LINE กลุ่มเดียว แทนการ loop ส่งหา admin ทีละคน
      await pushLine(LINE_GROUP_ID, alertMsg)
    }
  }

  return new Response('done', { status: 200 })
})
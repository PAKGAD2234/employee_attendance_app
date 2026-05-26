import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CLIENT_EMAIL = "firebase-adminsdk-fbsvc@massage-pos-4fb5b.iam.gserviceaccount.com"
const PROJECT_ID = "massage-pos-4fb5b"
const PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC8HcW4I/gLqTKO\nDpGrwdbJo15Bfo6SBNM7PXBGlHB3IkkvMeszJtrO0APZmIoEhev33/3F4oByPqOv\nv6FbIU7m5mNKxqc3Hb+X6Xurb1fjhHzPd0pC4QkDxTIg1TlzSLV5y5IuKAit1+uI\nmHJkTR+pZt4Df0gqx8rXi3WR23poPxxaZTHygRjSLw3VzCdu4Nf24BdOTx7CZYu5\nBRZbANgyzY7upphdL+46c1kJDFFrLIbaQ66tfnDpWJA2YRdxvwGnN/JGY/P3l5c6\nv6yJlhbsJQRcs7MA/akivY57IVxwjA/oYUXLQKQV4I8SnZCn9rcLp7uuoF/wWUUd\naQZiLGuJAgMBAAECggEALJ8dStARYua4DLVM/YJlyf+b+IomFGHbnxY0PzGvubqi\nxHShV0lUprD18NP7jRYdQndZ0WooULEmD6azhhPRDPlCPTcA7BR84XJrON+Y5+mB\n145yyYlqo3/Po7UgQwXQsjrFCnjJkj8A6i5LGBqpM3wolojHHAq3RUiZ00bN8tL5\nTz1ubnvGHas4rRydhLvOFILkaCxim/hVF8e2rUkcj6XwtCkiolZsIuXp/sLUzigT\n8GuUwrcIOr1pnhY9k0L6zTUnzJsRNBXcySTxdNqfFaUKm0ZTB2ffxmEuw+BQRy2g\n9ejPxq5Osz0HmrDuG+paSlNe3m6L5uj0tmMUX5XSmQKBgQDm1vtFci5pAjDz/kPZ\n3ty63mvrr6wXOyghTKhU60K5h3y3RXhd0NJaZmFkbgPLTLu8T0zy/wSttiULq2PJ\n1iVxf860dboJqlkvv8fPFSx3aEMpvDArP8nWUASzVejPBdytF2ZqYoFI+tUAUAzw\nA2lVuaNMZSOTSKMlYnTCDPjB/QKBgQDQnrJphq81myAcBtK4AS1o4iCD73KcBU1B\ntotvK/LA3UmKmSKnvQj/071tl3AdCcRnoQv5PdKqLlMOT/zbGVjTwmX9LLqmT9xu\nZY5rjwG8sRN1hqsyObceRCDSskp5nUaTEPo8iUtw6p4qK89dZixEJypddKjBM9aS\nW17NDc1vfQKBgQC1QbFjwlh20+WkcM7OUJR5lxSep/4075p/KzYyF9j43U4sijwN\nTl8d5K4sscYA6GuxXYNKerwtuow0MYvVfHVCPd0NDjPaSwxk1e4KyNF1oUS7jK02\nCIxv370RJC/9/thcgbdFabuilnKSIElIXSVkzrNO1Uut5qdUP472oEDj8QKBgQCY\n7DuL7xZwDQ40fSvphbNrtpZvIA67H4fKK616CJUhmxRVbHtiycbXALdSpjegkZBP\nBlZolVDfPqXTT/7h/GqIj2+Dbk5DqzbCFd+YKHP1hTfmZpkHcBczMG1/BQJis08Q\nbtl/loSeeN0HvKV8qXC5ZJxBdUpelUksb53GYd+9YQKBgQC4RQya4xn5WwufDWLN\ne7c1lIP2G2uGs9xZ4xzFb9kxFa9IW1hVjrWdshOUeblXIMLK9toeCMpMPZ2RPlE0\nbgwSKWPCBk+zVxtMwJr8YOcfiZoHcbTdTwrniNfF/va6Ra+PDho3Ah7zJ/QX3mev\nUxuDDhbQT1B08dyZIqPJyltJBA==\n-----END PRIVATE KEY-----\n"

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')
  const binary = atob(base64)
  const buffer = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) buffer[i] = binary.charCodeAt(i)
  return buffer.buffer
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const header = { alg: 'RS256', typ: 'JWT' }
  const enc = (obj: object) => btoa(JSON.stringify(obj)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_')
  const signingInput = `${enc(header)}.${enc(payload)}`
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToArrayBuffer(PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']
  )
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_')}`
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const data = await res.json()
  return data.access_token
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    })
  }

  const { title, body } = await req.json()
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  const { data: tokens } = await supabase.from('admin_tokens').select('token')
  if (!tokens || tokens.length === 0) return new Response('no tokens', { status: 200 })

  const accessToken = await getAccessToken()
  for (const { token } of tokens) {
    await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message: { token, notification: { title, body } } })
    })
  }
  return new Response('ok', { 
    status: 200,
    headers: { 'Access-Control-Allow-Origin': '*' }
  })
})
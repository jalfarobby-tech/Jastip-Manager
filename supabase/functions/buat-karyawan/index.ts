// Edge Function: pemilik toko membuat akun karyawan (email + password) dari dalam aplikasi.
// Deploy lewat Supabase Dashboard > Edge Functions > Deploy a new function, nama: buat-karyawan.
import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    })
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'Harus login.' }, 401)

    const b = await req.json()
    const email = String(b.email ?? '').trim().toLowerCase()
    const password = String(b.password ?? '')
    const name = String(b.name ?? '').trim().slice(0, 60) || email.split('@')[0]
    const role = b.role
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return json({ error: 'Format email tidak valid.' }, 400)
    if (password.length < 8) return json({ error: 'Password minimal 8 karakter.' }, 400)
    if (role !== 'pencatat' && role !== 'pembeli') return json({ error: 'Peran tidak valid.' }, 400)

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    // hanya pemilik toko itu yang boleh
    const { data: mine } = await admin.from('members').select('role')
      .eq('shop_id', b.shop).eq('user_id', user.id).maybeSingle()
    if (!mine || mine.role !== 'owner') return json({ error: 'Hanya pemilik yang boleh menambah anggota.' }, 403)

    // batas anggota per toko
    const { count } = await admin.from('members').select('user_id', { count: 'exact', head: true }).eq('shop_id', b.shop)
    if ((count ?? 0) >= 20) return json({ error: 'Jumlah anggota sudah mencapai batas (20).' }, 400)

    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
    if (created.error || !created.data.user) {
      const m = String(created.error?.message ?? '').toLowerCase()
      if (m.includes('already') || m.includes('exists') || m.includes('registered')) {
        return json({ error: 'Email ini sudah punya akun. Kosongkan kolom password lalu tambahkan sebagai anggota.' }, 409)
      }
      return json({ error: 'Akun belum bisa dibuat. Coba lagi.' }, 400)
    }
    const ins = await admin.from('members').insert({ shop_id: b.shop, user_id: created.data.user.id, role, name })
    if (ins.error) return json({ error: 'Akun dibuat, tapi belum bisa dimasukkan ke toko. Hubungi admin.' }, 500)
    return json({ ok: true })
  } catch (_e) {
    return json({ error: 'Terjadi kesalahan. Coba lagi.' }, 500)
  }
})

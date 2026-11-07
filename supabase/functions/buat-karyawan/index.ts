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

    // hanya pemilik toko itu yang boleh. Dicek dengan hak akses si pemanggil sendiri (aturan akses RLS tetap berlaku).
    const mine = await userClient.from('members').select('role')
      .eq('shop_id', b.shop).eq('user_id', user.id).maybeSingle()
    if (mine.error) return json({ error: 'Gagal memeriksa peran: ' + mine.error.message }, 500)
    if (!mine.data || mine.data.role !== 'owner') return json({ error: 'Hanya pemilik yang boleh menambah anggota.' }, 403)

    // batas anggota per toko
    const cnt = await userClient.from('members').select('user_id', { count: 'exact', head: true }).eq('shop_id', b.shop)
    if (!cnt.error && (cnt.count ?? 0) >= 20) return json({ error: 'Jumlah anggota sudah mencapai batas (20).' }, 400)

    const addMember = async () => {
      const r = await userClient.rpc('add_member', { p_shop: b.shop, p_email: email, p_role: role, p_name: name })
      return r.error ? r.error.message : ''
    }

    const created = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { karyawan: true },
    })
    if (created.error || !created.data.user) {
      const m = String(created.error?.message ?? '').toLowerCase()
      if (m.includes('already') || m.includes('exists') || m.includes('registered')) {
        // Email sudah punya akun: cukup masukkan sebagai anggota toko ini.
        const err = await addMember()
        if (err) return json({ error: 'Belum bisa menambahkan anggota: ' + err }, 400)
        return json({ ok: true, existing: true })
      }
      return json({ error: 'Akun belum bisa dibuat: ' + (created.error?.message ?? 'tidak diketahui') }, 400)
    }
    const err = await addMember()
    if (err) {
      // Batalkan akun yang baru dibuat supaya percobaan berikutnya bersih.
      await admin.auth.admin.deleteUser(created.data.user.id)
      return json({ error: 'Belum bisa menambahkan anggota: ' + err }, 500)
    }
    return json({ ok: true })
  } catch (_e) {
    return json({ error: 'Terjadi kesalahan. Coba lagi.' }, 500)
  }
})

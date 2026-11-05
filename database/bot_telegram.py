"""Kirim ringkasan harian Jastip Manager ke Telegram. Rahasia hanya dibaca dari environment, tidak pernah dicetak."""
import json, os, sys, urllib.request, urllib.error, datetime

SB = os.environ.get("SUPABASE_URL", "https://tibwgpqwroilzfyggyuz.supabase.co")
ANON = os.environ["SUPABASE_ANON"]
KUNCI = os.environ["BOT_KUNCI"]
TOKEN = os.environ["TG_TOKEN"]
CHAT = os.environ.get("TG_CHAT", "").strip()
TG = os.environ.get("TG_API", "https://api.telegram.org")

def call(url, body=None, headers=None):
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"Gagal {e.code} dari {url.split('/')[2]}: {e.read()[:200].decode(errors='replace')}".replace(TOKEN, "***"))

def rp(n): return "Rp" + f"{int(n):,}".replace(",", ".")

if not CHAT:  # cari chat ID otomatis dari pesan yang pernah dikirim ke bot
    ups = call(f"{TG}/bot{TOKEN}/getUpdates").get("result", [])
    ids = [u["message"]["chat"]["id"] for u in ups if "message" in u]
    if not ids: sys.exit("Chat ID belum ketemu: kirim /start ke botmu di Telegram, lalu jalankan ulang.")
    CHAT = str(ids[-1]); print("Chat ID terdeteksi:", CHAT, "(simpan sebagai secret TG_CHAT agar tetap)")

data = call(f"{SB}/rest/v1/rpc/bot_ringkasan", {"p_kunci": KUNCI}, {"apikey": ANON, "Authorization": "Bearer " + ANON})
today = datetime.date.today()
lines = [f"Ringkasan Jastip Manager, {today.strftime('%d/%m/%Y')}", ""]
if not data: lines.append("Belum ada trip aktif.")
for t in data:
    h = ""
    if t["deadline"]:
        d = (datetime.date.fromisoformat(t["deadline"]) - today).days
        h = f" (deadline {'hari ini' if d == 0 else str(d) + ' hari lagi' if d > 0 else 'lewat ' + str(-d) + ' hari'})"
    lines += [f"{t['trip']}{h}",
              f"- Pelanggan: {t['pelanggan']}, belum bayar: {t['belum_bayar']}",
              f"- Barang dipesan belum dibeli: {t['belum_dibeli']}",
              f"- Uang masuk: {rp(t['uang_masuk'])}", ""]
msg = "\n".join(lines).strip()
call(f"{TG}/bot{TOKEN}/sendMessage", {"chat_id": CHAT, "text": msg})
print("Terkirim.")

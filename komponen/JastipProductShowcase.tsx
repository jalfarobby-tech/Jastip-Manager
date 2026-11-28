'use client'
/**
 * JastipProductShowcase
 * Demo interaktif Jastip Manager: 3 adegan, auto-play loop tanpa suara (~14 detik).
 *
 * Kebutuhan: react >= 18, framer-motion >= 11 (import dari 'framer-motion'), tailwindcss >= 3.
 * Tidak perlu tailwind.config khusus: semua warna asli aplikasi dipasang sebagai
 * variabel CSS di elemen akar komponen ini (LIGHT dan DARK di bawah, nilainya diambil
 * dari :root aplikasi). Props: bare (tanpa judul/latar), theme ('light' | 'dark' | 'auto'). Pastikan file ini masuk ke `content` Tailwind kamu.
 *
 * Huruf asli aplikasi: Plus Jakarta Sans. Muat sekali di <head> situsmu:
 *   <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
 *
 * Pemakaian:  <JastipProductShowcase />
 */
import { useEffect, useRef, useState, type CSSProperties, type ReactNode, type RefObject } from 'react'
import { AnimatePresence, animate, motion, useInView, useMotionValue, useReducedMotion, useTransform } from 'framer-motion'

/* ---------- Warna & huruf asli Jastip Manager (mode terang) ---------- */
const FONT = "'Plus Jakarta Sans', system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
const LIGHT = {
  '--paper': '#f3f0e8', '--surface': '#fffdf9', '--sunken': '#f0ece2', '--rule': '#e3ddd0', '--rule-strong': '#b3ab9a',
  '--ink': '#17171c', '--muted': '#5b584f',
  '--blue': '#2740d8', '--blue-deep': '#2433b5', '--blue-soft': '#e8ecff',
  '--hi': '#ffe14d', '--hi-ink': '#2a2300',
  '--red': '#cf2f29', '--red-soft': '#fdecea', '--green': '#0f7a3d', '--green-soft': '#e5f5ec', '--amber': '#97580a',
  '--bezel': '#17171c', '--flash': '#e8ecff',
}
/* Mode gelap = :root gelap aplikasi */
const DARK = {
  '--paper': '#0b0e15', '--surface': '#141824', '--sunken': '#1b2030', '--rule': '#262c3d', '--rule-strong': '#5a647d',
  '--ink': '#eef1f9', '--muted': '#a3acc0',
  '--blue': '#93a5ff', '--blue-deep': '#2433b5', '--blue-soft': '#1d2548',
  '--hi': '#ffe14d', '--hi-ink': '#2a2300',
  '--red': '#ff8d85', '--red-soft': '#3a1c1b', '--green': '#62d18f', '--green-soft': '#16301f', '--amber': '#f2b95b',
  '--bezel': '#05070b', '--flash': '#1d2548',
}
const tokens = (dark: boolean) => ({ ...(dark ? DARK : LIGHT), fontFamily: FONT }) as CSSProperties

/* Satu kurva gerak untuk semuanya */
const SPRING = { type: 'spring', stiffness: 120, damping: 20 } as const

/* ---------- Adegan ---------- */
type Scene = { title: string; body: string; dur: number; steps: number[] }
const SCENES: Scene[] = [
  {
    title: 'Catat pesanan',
    body: 'Tulis nama dan kode barang, pesanan langsung rapi dan total tagihannya terhitung sendiri.',
    dur: 4800,
    steps: [700, 1900, 2150, 3600], // 1 kursor jalan, 2 klik, 3 kartu masuk, 4 kursor pergi
  },
  {
    title: 'Pantau untung otomatis',
    body: 'Modal barang, ongkir, dan untung bersih dihitung otomatis. Kamu tidak perlu membuka kalkulator.',
    dur: 4600,
    steps: [300, 800, 1150, 1500, 2300], // 1 zoom, 2 omzet, 3 modal+ongkir, 4 untung, 5 margin
  },
  {
    title: 'Kirim pengingat',
    body: 'Pelanggan belum bayar? Satu ketukan, pengingat tagihan langsung terkirim ke WhatsApp mereka.',
    dur: 4600,
    steps: [900, 2000, 2200, 2900], // 1 kursor jalan, 2 klik, 3 terkirim + toast, (4 sisa)
  },
]

const rp = (n: number) => 'Rp' + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')

/* ---------- Ikon (garis 1.75, sama seperti di aplikasi) ---------- */
const P: Record<string, string> = {
  home: 'M4 5h6v6H4zM14 5h6v6h-6zM4 15h6v4H4zM14 15h6v4h-6z',
  tag: 'M3 12V4h8l10 10-8 8L3 12zM7.5 8.5h.01',
  cart: 'M3 4h2l2.2 10h10.6L20 7H6M9 19h.01M17 19h.01',
  users: 'M9 11a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM2.5 20c.6-3.4 3.2-5 6.5-5s5.9 1.6 6.5 5M16 4.5a3.3 3.3 0 010 6.3M18 15.3c1.9.6 3.1 2 3.5 4.7',
  box: 'M3.5 7.5L12 3l8.5 4.5v9L12 21l-8.5-4.5zM3.5 7.5L12 12l8.5-4.5M12 12v9',
  plus: 'M12 5v14M5 12h14',
  chev: 'M6 9l6 6 6-6',
  menu: 'M4 7h16M4 12h16M4 17h10',
  check: 'M5 12.5l4.5 4.5L19 7.5',
}
function Ico({ n, size = 20, className = '' }: { n: keyof typeof P; size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>
      <path d={P[n]} />
    </svg>
  )
}

/* ---------- Angka yang naik ---------- */
function Count({ to, run, className = '' }: { to: number; run: boolean; className?: string }) {
  const reduce = useReducedMotion()
  const mv = useMotionValue(0)
  const txt = useTransform(mv, (v) => rp(v))
  useEffect(() => {
    if (!run) {
      mv.set(0)
      return
    }
    if (reduce) {
      mv.set(to)
      return
    }
    const c = animate(mv, to, SPRING)
    return () => c.stop()
  }, [run, to, reduce, mv])
  return <motion.span className={className}>{txt}</motion.span>
}

/* ---------- Potongan tampilan aplikasi ---------- */
const Code = ({ children }: { children: ReactNode }) => (
  <span className="rounded-[5px] bg-[var(--hi)] px-[5px] py-[1px] text-[10.5px] font-extrabold leading-none text-[var(--hi-ink)]">{children}</span>
)

function Pill({ tone, children }: { tone: 'bad' | 'ok'; children: ReactNode }) {
  const c = tone === 'bad' ? 'bg-[var(--red-soft)] text-[var(--red)]' : 'bg-[var(--green-soft)] text-[var(--green)]'
  return <span className={`inline-flex shrink-0 items-center gap-1 rounded-full px-[10px] py-[5px] text-[11px] font-extrabold ${c}`}>{children}</span>
}

function CustomerRow({ initial, name, codes, total, paid, fresh }: { initial: string; name: string; codes: [string, string][]; total: number; paid: boolean; fresh?: boolean }) {
  return (
    <motion.li
      layout
      initial={fresh ? { opacity: 0, y: -28, scale: 0.96 } : false}
      animate={fresh ? { opacity: 1, y: 0, scale: 1, backgroundColor: ['var(--flash)', 'var(--surface)'] } : undefined}
      transition={fresh ? { ...SPRING, backgroundColor: { duration: 1.6, delay: 0.35, ease: 'easeOut' } } : SPRING}
      className="flex items-center gap-3 border-b border-[var(--rule)] px-[14px] py-[12px] last:border-b-0"
    >
      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-[10px] bg-[var(--sunken)] text-[15px] font-extrabold text-[var(--ink)]">{initial}</span>
      <span className="min-w-0 flex-1">
        <b className="block text-[14px] font-bold leading-tight text-[var(--ink)]">{name}</b>
        <span className="mt-[5px] flex flex-wrap items-center gap-[6px]">
          {codes.map(([k, q]) => (
            <span key={k} className="flex items-center gap-[3px] text-[11px] font-semibold text-[var(--muted)]">
              <Code>{k}</Code>×{q}
            </span>
          ))}
        </span>
      </span>
      <span className="flex flex-col items-end gap-[6px]">
        <b className="text-[13px] font-bold tabular-nums text-[var(--ink)]">{rp(total)}</b>
        <Pill tone={paid ? 'ok' : 'bad'}>{paid ? 'Lunas' : 'Belum bayar'}</Pill>
      </span>
    </motion.li>
  )
}

function PelangganScreen({ added, btnRef, pressed }: { added: boolean; btnRef: RefObject<HTMLButtonElement>; pressed: boolean }) {
  return (
    <div className="px-[14px] pt-[14px]">
      <div className="mb-[10px] flex items-end justify-between">
        <h4 className="text-[20px] font-bold tracking-[-0.012em] text-[var(--ink)]">Pelanggan</h4>
        <span className="pb-[2px] text-[12px] font-semibold text-[var(--muted)]">{added ? 3 : 2} orang</span>
      </div>
      <motion.button
        ref={btnRef}
        type="button"
        tabIndex={-1}
        animate={{ scale: pressed ? 0.97 : 1 }}
        transition={SPRING}
        className="mb-3 flex min-h-[48px] w-full items-center justify-center gap-2 rounded-[14px] bg-[var(--blue-deep)] text-[14px] font-bold text-white"
      >
        <Ico n="plus" size={18} /> Pesanan baru
      </motion.button>
      <ul className="overflow-hidden rounded-2xl border border-[var(--rule)] bg-[var(--surface)]">
        <AnimatePresence initial={false}>
          {added && <CustomerRow key="anisa" fresh initial="A" name="Anisa" codes={[['A01', '2'], ['B01', '1']]} total={557000} paid={false} />}
        </AnimatePresence>
        <CustomerRow initial="D" name="Dewi" codes={[['A02', '3']]} total={387000} paid={false} />
        <CustomerRow initial="S" name="Sinta" codes={[['A01', '2'], ['A03', '1']]} total={339000} paid />
      </ul>
    </div>
  )
}

function WorkRow({ tone, title, sub, children }: { tone: 'red' | 'amber'; title: string; sub: string; children: ReactNode }) {
  const bar = tone === 'red' ? 'bg-[var(--red)]' : 'bg-[var(--amber)]'
  return (
    <div className="flex items-center gap-3 border-b border-[var(--rule)] px-[14px] py-[12px] last:border-b-0">
      <span className={`h-9 w-[5px] shrink-0 rounded-[3px] ${bar}`} />
      <span className="min-w-0 flex-1">
        <b className="block text-[13.5px] font-bold leading-tight text-[var(--ink)]">{title}</b>
        <small className="mt-[3px] block text-[11.5px] leading-snug text-[var(--muted)]">{sub}</small>
      </span>
      {children}
    </div>
  )
}

function BerandaScreen({ step, scene, tagihRef }: { step: number; scene: number; tagihRef: RefObject<HTMLButtonElement>; }) {
  const s2 = scene === 1
  const s3 = scene === 2
  const sent = s3 && step >= 3
  const busy = s3 && step === 2
  const run = (n: number) => s3 || (s2 && step >= n)
  return (
    <motion.div
      className="px-[14px] pt-[14px]"
      style={{ transformOrigin: '50% 30%' }}
      animate={{ y: s2 && step >= 1 ? -208 : 0, scale: s2 && step >= 1 ? 1.05 : 1 }}
      transition={SPRING}
    >
      <h4 className="mb-[10px] text-[15px] font-bold tracking-[-0.012em] text-[var(--ink)]">Perlu dikerjakan</h4>
      <div className="overflow-hidden rounded-2xl border border-[var(--rule)] bg-[var(--surface)]">
        <WorkRow tone="red" title="Menunggu pembayaran" sub="Anisa, Maya. Sisa Rp944.500">
          <AnimatePresence mode="wait" initial={false}>
            {sent ? (
              <motion.span key="ok" initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} transition={SPRING}>
                <Pill tone="ok"><Ico n="check" size={12} /> Sudah ditagih</Pill>
              </motion.span>
            ) : (
              <motion.button
                key="tagih"
                ref={tagihRef}
                type="button"
                tabIndex={-1}
                exit={{ opacity: 0 }}
                animate={{ scale: busy ? 0.96 : 1 }}
                transition={SPRING}
                className="min-w-[86px] rounded-full border-[1.5px] border-[var(--rule-strong)] bg-[var(--surface)] px-[14px] py-[6px] text-center text-[12px] font-bold text-[var(--ink)]"
              >
                {busy ? 'Mengirim…' : 'Tagih'}
              </motion.button>
            )}
          </AnimatePresence>
        </WorkRow>
        <WorkRow tone="amber" title="Barang belum dibeli" sub="Olive Young (1)">
          <span className="rounded-full border border-[var(--rule)] px-[12px] py-[5px] text-[11.5px] font-bold text-[var(--muted)]">Belanja</span>
        </WorkRow>
      </div>

      <div className="mt-[18px] rounded-[20px] border border-[var(--rule)] bg-[var(--surface)] p-[16px]">
        <div className="text-[11.5px] font-semibold text-[var(--muted)]">Perkiraan untung bersih</div>
        <div className="mt-[2px] text-[30px] font-extrabold leading-[1.1] tracking-[-0.02em] text-[var(--ink)]">
          <Count to={168000} run={run(4)} />
        </div>
        <motion.div className="mt-[2px] text-[12px] font-bold text-[var(--green)]" animate={{ opacity: run(5) ? 1 : 0 }} transition={SPRING}>
          Margin 9% dari omzet
        </motion.div>
        <div className="mt-[10px]">
          {([
            ['Omzet (total tagihan)', 1870000, 2],
            ['Modal barang', 1517000, 3],
            ['Ongkir', 185000, 3],
          ] as const).map(([k, v, n]) => (
            <div key={k} className="flex items-center justify-between border-t border-[var(--rule)] py-[9px] text-[12.5px] font-semibold text-[var(--muted)]">
              <span>{k}</span>
              <Count to={v} run={run(n)} className="font-bold tabular-nums text-[var(--ink)]" />
            </div>
          ))}
        </div>
      </div>
    </motion.div>
  )
}

function BottomNav({ on }: { on: 'home' | 'users' }) {
  const items: [keyof typeof P, string, string][] = [
    ['home', 'Beranda', 'home'],
    ['tag', 'Barang', 'tag'],
    ['cart', 'Belanja', 'cart'],
    ['users', 'Pelanggan', 'users'],
    ['box', 'Kirim', 'box'],
  ]
  return (
    <div className="absolute inset-x-0 bottom-0 flex h-[66px] items-start justify-around border-t border-[var(--rule)] bg-[var(--surface)] px-1 pt-[7px]">
      {items.map(([ic, label, key]) => {
        const active = key === on
        return (
          <div key={label} className={`flex w-[58px] flex-col items-center gap-[3px] text-[10.5px] font-semibold ${active ? 'text-[var(--blue)]' : 'text-[var(--muted)]'}`}>
            <span className={`grid h-[28px] w-[46px] place-items-center rounded-full transition-colors duration-300 ${active ? 'bg-[var(--blue-soft)]' : ''}`}>
              <Ico n={ic} size={19} />
            </span>
            {label}
          </div>
        )
      })}
    </div>
  )
}

function Cursor({ x, y, show, pressed }: { x: ReturnType<typeof useMotionValue<number>>; y: ReturnType<typeof useMotionValue<number>>; show: boolean; pressed: boolean }) {
  return (
    <motion.div className="pointer-events-none absolute left-0 top-0 z-30" style={{ x, y }} animate={{ opacity: show ? 1 : 0 }} transition={{ duration: 0.3 }}>
      <motion.span
        className="absolute -left-4 -top-4 h-8 w-8 rounded-full bg-[var(--blue)]"
        initial={false}
        animate={{ opacity: pressed ? 0.22 : 0, scale: pressed ? 1 : 0.4 }}
        transition={SPRING}
      />
      <svg width="22" height="22" viewBox="0 0 24 24" className="relative drop-shadow-[0_2px_3px_rgba(0,0,0,.35)]" aria-hidden>
        <path d="M5 3l14 7.2-6 1.8-2.2 6.2z" fill="var(--ink)" stroke="var(--surface)" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
    </motion.div>
  )
}

/* ---------- Bingkai HP + isi ---------- */
function Phone({ active, step }: { active: number; step: number }) {
  const screenRef = useRef<HTMLDivElement>(null)
  const addRef = useRef<HTMLButtonElement>(null)
  const tagihRef = useRef<HTMLButtonElement>(null)
  const cx = useMotionValue(300)
  const cy = useMotionValue(560)
  const [pressed, setPressed] = useState(false)
  const reduce = useReducedMotion()

  const pt = (el: HTMLElement | null) => {
    const a = screenRef.current?.getBoundingClientRect()
    const b = el?.getBoundingClientRect()
    if (!a || !b || !screenRef.current) return null
    const k = a.width / screenRef.current.offsetWidth || 1 // kompensasi skala di layar kecil
    return { x: (b.left - a.left + b.width * 0.62) / k, y: (b.top - a.top + b.height * 0.58) / k }
  }
  const go = (p: { x: number; y: number } | null) => {
    if (!p) return
    if (reduce) {
      cx.set(p.x)
      cy.set(p.y)
    } else {
      animate(cx, p.x, SPRING)
      animate(cy, p.y, SPRING)
    }
  }

  // kursor bergerak sesuai langkah
  useEffect(() => {
    if (active === 0) {
      if (step === 1) go(pt(addRef.current))
      if (step === 4) go({ x: 290, y: 470 })
    }
    if (active === 2 && step === 1) go(pt(tagihRef.current))
    if (active === 2 && step === 3) go({ x: 250, y: 380 })
    if (step === 0) {
      cx.set(300)
      cy.set(560)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, step])

  // efek tekan
  useEffect(() => {
    const click = (active === 0 && step === 2) || (active === 2 && step === 2)
    setPressed(click)
    if (!click) return
    const t = setTimeout(() => setPressed(false), 320)
    return () => clearTimeout(t)
  }, [active, step])

  const showCursor = (active === 0 && step >= 1 && step < 4) || (active === 2 && step >= 1 && step < 3)
  const screen = active === 0 ? 'cust' : 'home'

  return (
    <div className="relative mx-auto h-[700px] w-[340px] rounded-[48px] bg-[var(--bezel)] p-[9px] ring-1 ring-[var(--rule)] shadow-[0_44px_80px_-42px_rgba(23,23,28,.5),0_14px_28px_-18px_rgba(23,23,28,.35)]">
      <div ref={screenRef} className="relative h-full w-full overflow-hidden rounded-[39px] bg-[var(--paper)]">
        {/* pulau kamera */}
        <div className="absolute left-1/2 top-[9px] z-40 h-[22px] w-[84px] -translate-x-1/2 rounded-full bg-[var(--bezel)]" />
        {/* bilah atas */}
        <div className="absolute inset-x-0 top-0 z-20 flex h-[82px] items-end gap-2 border-b border-[var(--rule)] bg-[var(--surface)] px-[12px] pb-[9px]">
          <span className="relative h-[30px] w-[30px] shrink-0 rounded-[9px] bg-[var(--blue)]">
            <span className="absolute left-[7px] top-[8px] h-[7px] w-[16px] rounded-[2px] bg-[var(--hi)]" />
          </span>
          <span className="flex h-[38px] min-w-0 flex-1 items-center justify-between rounded-[10px] bg-[var(--sunken)] px-3 text-[12.5px] font-bold text-[var(--ink)]">
            <span className="truncate">PO Korea November</span>
            <Ico n="chev" size={15} className="shrink-0 text-[var(--muted)]" />
          </span>
          <span className="flex h-[38px] shrink-0 items-center gap-[6px] rounded-full border-[1.5px] border-[var(--rule-strong)] bg-[var(--surface)] pl-[10px] pr-[12px] text-[12.5px] font-bold text-[var(--ink)]">
            <Ico n="menu" size={16} /> Menu
          </span>
        </div>

        <div className="absolute inset-x-0 bottom-[66px] top-[82px] overflow-hidden">
          <AnimatePresence initial={false}>
            <motion.div
              key={screen}
              className="absolute inset-0"
              initial={{ opacity: 0, x: 14 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -14 }}
              transition={SPRING}
            >
              {screen === 'cust' ? (
                <PelangganScreen added={active === 0 && step >= 3} btnRef={addRef} pressed={pressed && active === 0} />
              ) : (
                <BerandaScreen step={step} scene={active} tagihRef={tagihRef} />
              )}
            </motion.div>
          </AnimatePresence>
        </div>

        <BottomNav on={screen === 'cust' ? 'users' : 'home'} />

        {/* toast hijau */}
        <AnimatePresence>
          {active === 2 && step >= 3 && (
            <motion.div
              key="toast"
              role="status"
              className="absolute inset-x-0 bottom-[84px] z-30 mx-auto flex w-max items-center gap-2 rounded-[14px] bg-[var(--ink)] px-4 py-3 text-[13px] font-semibold text-[var(--surface)] shadow-[0_10px_28px_-10px_rgba(0,0,0,.5)]"
              initial={{ opacity: 0, y: 18, scale: 0.96 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 10 }}
              transition={SPRING}
            >
              <span className="grid h-5 w-5 place-items-center rounded-full bg-[#2fb36d] text-white">
                <Ico n="check" size={13} />
              </span>
              Pengingat terkirim
            </motion.div>
          )}
        </AnimatePresence>

        <Cursor x={cx} y={cy} show={showCursor} pressed={pressed} />
      </div>
    </div>
  )
}

/* ---------- Komponen utama ---------- */
type Props = {
  className?: string
  /** true = tanpa latar, padding, dan judul besar (untuk disisipkan di halaman yang sudah punya judul sendiri) */
  bare?: boolean
  /** 'auto' mengikuti pengaturan terang/gelap perangkat */
  theme?: 'light' | 'dark' | 'auto'
}

export default function JastipProductShowcase({ className = '', bare = false, theme = 'light' }: Props) {
  const [dark, setDark] = useState(theme === 'dark')
  useEffect(() => {
    if (theme !== 'auto') return setDark(theme === 'dark')
    const m = window.matchMedia('(prefers-color-scheme: dark)')
    const f = () => setDark(m.matches)
    f()
    m.addEventListener('change', f)
    return () => m.removeEventListener('change', f)
  }, [theme])
  const rootRef = useRef<HTMLDivElement>(null)
  const inView = useInView(rootRef, { amount: 0.35 })
  const reduce = useReducedMotion()
  const [st, setSt] = useState({ a: 0, s: 0, k: 0 }) // k: penanda mulai ulang saat poin diklik

  useEffect(() => {
    if (!inView) return
    const sc = SCENES[st.a]
    const a = st.a
    const timers: ReturnType<typeof setTimeout>[] = []
    sc.steps.forEach((ms, i) => timers.push(setTimeout(() => setSt((p) => (p.a === a ? { ...p, s: i + 1 } : p)), ms)))
    timers.push(setTimeout(() => setSt((p) => ({ a: (p.a + 1) % SCENES.length, s: 0, k: p.k })), sc.dur))
    return () => timers.forEach(clearTimeout)
  }, [st.a, st.k, inView])

  const pick = (i: number) => setSt((p) => ({ a: i, s: 0, k: p.k + 1 }))

  return (
    <section
      ref={rootRef}
      style={tokens(dark)}
      className={`w-full text-[var(--ink)] ${bare ? '' : 'bg-[var(--paper)] px-5 py-16 md:px-10 md:py-24'} ${className}`}
      aria-label="Demo Jastip Manager"
    >
      <div className="mx-auto grid max-w-[1100px] items-center gap-6 lg:grid-cols-[1fr_auto] lg:gap-20">
        {/* kiri: teks */}
        <div>
          {!bare && (
            <>
              <p className="mb-3 text-[14px] font-bold text-[var(--blue)]">Jastip Manager</p>
              <h2 className="max-w-[16em] text-[clamp(1.9rem,4.4vw,2.9rem)] font-extrabold leading-[1.08] tracking-[-0.025em]">Dari chat pelanggan sampai untung, tanpa catatan manual.</h2>
            </>
          )}
          <div className={`${bare ? '' : 'mt-9'} flex flex-col gap-1`} role="tablist" aria-label="Adegan demo">
            {SCENES.map((s, i) => {
              const on = i === st.a
              const done = i < st.a
              return (
                <button
                  key={s.title}
                  type="button"
                  role="tab"
                  aria-selected={on}
                  onClick={() => pick(i)}
                  className={`group w-full rounded-xl px-1 py-3 text-left lg:py-4 transition-opacity duration-300 ${on ? 'opacity-100' : 'opacity-55 hover:opacity-90'}`}
                >
                  <span className="flex items-baseline gap-3">
                    <span className="text-[13px] font-bold tabular-nums text-[var(--muted)]">0{i + 1}</span>
                    <span className="text-[1.15rem] font-extrabold tracking-[-0.015em] lg:text-[1.35rem]">{s.title}</span>
                  </span>
                  <AnimatePresence initial={false}>
                    {on && (
                      <motion.span
                        key="b"
                        className="block overflow-hidden pl-[30px]"
                        initial={{ height: 0, opacity: 0 }}
                        animate={{ height: 'auto', opacity: 1 }}
                        exit={{ height: 0, opacity: 0 }}
                        transition={SPRING}
                      >
                        <span className="block max-w-[30em] pt-2 text-[1rem] leading-[1.55] text-[var(--muted)]">{s.body}</span>
                      </motion.span>
                    )}
                  </AnimatePresence>
                  <span className="mt-3 block h-[2px] lg:mt-4 overflow-hidden rounded-full bg-[var(--rule)]">
                    {on && inView && !reduce ? (
                      <motion.span key={`${st.k}-${st.a}`} className="block h-full origin-left bg-[var(--blue)]" initial={{ scaleX: 0 }} animate={{ scaleX: 1 }} transition={{ duration: s.dur / 1000, ease: 'linear' }} />
                    ) : (
                      <span className="block h-full origin-left bg-[var(--blue)]" style={{ transform: `scaleX(${done || (on && reduce) ? 1 : 0})` }} />
                    )}
                  </span>
                </button>
              )
            })}
          </div>
        </div>

        {/* kanan: HP */}
        <div className="order-first flex justify-center max-lg:-mb-[70px] lg:order-none lg:justify-end">
          <div className="max-lg:origin-top max-lg:scale-[.9]">
            <Phone active={st.a} step={st.s} />
          </div>
        </div>
      </div>
    </section>
  )
}

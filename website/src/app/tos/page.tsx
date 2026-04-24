'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';

const sections = [
  {
    title: '1. Acceptance',
    content: 'By downloading, installing, or using PeerChat ("the App"), you agree to be bound by these Terms. If you do not agree, do not use the App.',
  },
  {
    title: '2. Description of Service',
    content: 'PeerChat is a free, open-source, peer-to-peer encrypted messaging and file transfer application. All communication occurs directly between user devices via Bluetooth Low Energy (BLE), WiFi Direct, and WiFi Hotspot. No central servers are involved in message routing.',
  },
  {
    title: '3. Eligibility',
    content: 'You must be at least 13 years old to use PeerChat and legally permitted to use it in your jurisdiction.',
  },
  {
    title: '4. User Identity & Usernames',
    content: 'Authenticated users may set a custom display username. Usernames must be unique — a Firestore registry is used solely to enforce uniqueness by associating your email with your chosen username. No other personal data is stored server-side. Guest users have a deterministic name generated from their cryptographic key.',
  },
  {
    title: '5. Acceptable Use',
    content: 'You agree not to: transmit unlawful, harmful, or defamatory content; violate applicable laws; reverse-engineer or exploit the App beyond the open-source license scope; or conduct denial-of-service attacks against the mesh.',
  },
  {
    title: '6. No Warranty',
    content: 'PeerChat is provided "as is" without warranty. We make no guarantees regarding message delivery, uptime, or uninterrupted service. The mesh is best-effort by design.',
  },
  {
    title: '7. Limitation of Liability',
    content: 'To the maximum extent permitted by law, PeerChat and its maintainers shall not be liable for any direct, indirect, incidental, or consequential damages from use or inability to use the App.',
  },
];

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-[var(--color-ink)] text-[var(--color-mist)] flex flex-col">
      <main className="max-w-5xl mx-auto px-6 pt-16 pb-24 flex-1 w-full">
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-12 lg:gap-20 items-start">
          
          {/* Left: Scrollable Points */}
          <div className="space-y-12">
            <header>
              <motion.p 
                initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
                className="text-[10px] font-[family-name:var(--font-mono)] font-bold text-[var(--color-ember)] uppercase tracking-[0.2em] mb-4"
              >
                Terms of Service
              </motion.p>
              <motion.h1 
                initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
                className="font-[family-name:var(--font-display)] font-black text-[var(--color-ivory)] text-4xl lg:text-5xl tracking-tight mb-6"
              >
                Simple terms <br/><span className="text-[var(--color-ash)]">for a simple mesh.</span>
              </motion.h1>
            </header>

            <div className="space-y-10">
              {sections.map((s, i) => (
                <motion.section 
                  key={s.title}
                  initial={{ opacity: 0, x: -20 }}
                  whileInView={{ opacity: 1, x: 0 }}
                  viewport={{ once: true, margin: "-50px" }}
                  transition={{ delay: i * 0.05 }}
                  className="group"
                >
                  <h2 className="font-[family-name:var(--font-display)] font-bold text-lg text-[var(--color-ivory)] mb-3 group-hover:text-[var(--color-ember)] transition-colors">
                    {s.title}
                  </h2>
                  <p className="text-sm leading-relaxed text-[var(--color-ash)] max-w-2xl">
                    {s.content}
                  </p>
                </motion.section>
              ))}
              
              {/* Extra sections with links */}
              <motion.section initial={{ opacity: 0, x: -20 }} whileInView={{ opacity: 1, x: 0 }} viewport={{ once: true }} className="group">
                <h2 className="font-[family-name:var(--font-display)] font-bold text-lg text-[var(--color-ivory)] mb-3 group-hover:text-[var(--color-ember)] transition-colors">8. License & Changes</h2>
                <p className="text-sm leading-relaxed text-[var(--color-ash)] max-w-2xl">
                  Source code is available on <Link href="https://github.com/Mathi4Raja/P2P-app" target="_blank" className="text-[var(--color-ember)] hover:underline">GitHub</Link>. 
                  We may update these terms; material changes will be noted in the <Link href="/changelog" className="text-[var(--color-ember)] hover:underline">Changelog</Link>.
                </p>
              </motion.section>
            </div>
          </div>

          {/* Right: Sticky Center Block */}
          <aside className="lg:sticky lg:top-1/2 lg:-translate-y-1/2 space-y-6">
            <motion.div 
              initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} transition={{ delay: 0.3 }}
              className="rounded-2xl bg-[var(--color-charcoal)] border border-[var(--color-slate)]/40 p-6 shadow-2xl"
              style={{ background: 'linear-gradient(145deg, rgba(15,14,24,1) 0%, rgba(24,22,38,0.5) 100%)' }}
            >
              <div className="mb-6">
                <p className="text-[10px] font-[family-name:var(--font-mono)] text-[var(--color-ash)] uppercase tracking-widest mb-1">Effective Date</p>
                <p className="text-sm font-bold text-[var(--color-ivory)]">April 25, 2026</p>
              </div>

              <div className="space-y-4">
                <div className="p-4 rounded-xl bg-[var(--color-sage)]/5 border border-[var(--color-sage)]/10">
                  <p className="text-[10px] font-[family-name:var(--font-mono)] text-[var(--color-sage)] uppercase tracking-widest mb-2">TL;DR</p>
                  <p className="text-xs leading-relaxed text-[var(--color-mist)]">
                    Free, open-source, and P2P. No warranties provided. You own your data, and we don't route it through any servers.
                  </p>
                </div>

                <Link href="https://github.com/Mathi4Raja/P2P-app" target="_blank" className="flex items-center justify-between p-3 rounded-xl hover:bg-white/5 border border-transparent hover:border-white/10 transition-all group">
                  <span className="text-xs font-semibold text-[var(--color-ivory)]">Source Code</span>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="group-hover:translate-x-1 transition-transform">
                    <path d="M5 12h14M12 5l7 7-7 7"/>
                  </svg>
                </Link>
              </div>
            </motion.div>
          </aside>
        </div>
      </main>

      {/* Sticky Footer */}
      <footer className="sticky bottom-0 z-30 w-full border-t border-[var(--color-slate)]/20 py-4 px-6 backdrop-blur-md bg-[var(--color-ink)]/70">
        <div className="max-w-5xl mx-auto flex flex-col sm:flex-row justify-between items-center gap-4">
          <div className="flex items-center gap-6">
            <p className="font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-ash)] uppercase tracking-wider">
              © {new Date().getFullYear()} PeerChat
            </p>
            <Link href="/" className="text-xs font-[family-name:var(--font-mono)] text-[var(--color-ash)] hover:text-[var(--color-ember)] flex items-center gap-1.5 transition-colors">
              <svg width="10" height="10" viewBox="0 0 12 12" fill="none"><path d="M7.5 2L3.5 6L7.5 10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>
              Back Home
            </Link>
          </div>
          <nav className="flex gap-6">
            {[
              { label: 'Changelog', href: '/changelog' },
              { label: 'Donate', href: '/donateus' },
              { label: 'Terms', href: '/tos' },
              { label: 'Privacy', href: '/policies' },
            ].map((l) => (
              <Link
                key={l.label}
                href={l.href}
                className="text-[10px] font-[family-name:var(--font-mono)] font-bold uppercase tracking-widest text-[var(--color-ash)] hover:text-[var(--color-ember)] transition-colors"
              >
                {l.label}
              </Link>
            ))}
          </nav>
        </div>
      </footer>
    </div>
  );
}

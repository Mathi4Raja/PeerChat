'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';

const sections = [
  {
    title: '1. No Tracking or Analytics',
    content: 'PeerChat does not collect, store, or sell any personal data for analytics, advertising, or profiling. There are no tracking SDKs or cookies in the App.',
  },
  {
    title: '2. Username Registry (Firestore)',
    content: 'If you are an authenticated user and set a custom username, a single record containing your email address and chosen username is written to a private Firestore collection. This is used exclusively to enforce global username uniqueness. This data is not shared with third parties and is not used for any purpose other than uniqueness checking. Guest users are not in this registry.',
  },
  {
    title: '3. Data Stored on Your Device',
    content: 'The following is stored locally only: (a) cryptographic key pair — generated on first launch, stored in system keystore; (b) messages and files — local SQLite database, never uploaded; (c) peer identities — display names and public keys of connected peers; (d) notification settings and custom username. Uninstalling permanently deletes all of the above.',
  },
  {
    title: '4. Authentication (Optional)',
    content: 'If you sign in with Google, PeerChat uses Google Sign-In solely to associate your email with your local identity. Your email is stored on-device in secure storage and in the Firestore username registry. Google\'s own Privacy Policy governs the OAuth flow.',
  },
  {
    title: '5. Bluetooth & Wi-Fi Permissions',
    content: 'Required strictly for peer discovery and data transfer. These permissions are never used to scan for or report device locations to any third party.',
  },
  {
    title: '6. Open Source Verification',
    content: (
      <>
        All privacy claims can be independently verified by auditing the source code available on{' '}
        <a href="https://github.com/Mathi4Raja/P2P-app" target="_blank" rel="noopener noreferrer" className="text-[var(--color-ember)] hover:underline">
          GitHub
        </a>.
      </>
    ),
  },
  {
    title: '7. Changes',
    content: (
      <>
        We may update this Privacy Policy from time to time. Material changes will be noted in the{' '}
        <Link href="/changelog" className="text-[var(--color-ember)] hover:underline">
          Changelog
        </Link>{' '}
        with an updated effective date.
      </>
    ),
  },
];

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-[var(--color-ink)] text-[var(--color-mist)] flex flex-col">
      <main className="max-w-5xl mx-auto px-6 pt-16 pb-10 flex-1 w-full">
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-12 lg:gap-20 items-start">
          
          {/* Left: Scrollable Points */}
          <div className="space-y-12">
            <header>
              <motion.p 
                initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
                className="text-[10px] font-[family-name:var(--font-mono)] font-bold text-[var(--color-ember)] uppercase tracking-[0.2em] mb-4"
              >
                Privacy Policy
              </motion.p>
              <motion.h1 
                initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
                className="font-[family-name:var(--font-display)] font-black text-[var(--color-ivory)] text-4xl lg:text-5xl tracking-tight mb-6"
              >
                Your privacy is <br/><span className="text-[var(--color-ash)]">not for sale.</span>
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
                <div className="p-4 rounded-xl bg-[var(--color-ember)]/5 border border-[var(--color-ember)]/10">
                  <p className="text-[10px] font-[family-name:var(--font-mono)] text-[var(--color-ember)] uppercase tracking-widest mb-2">TL;DR</p>
                  <p className="text-xs leading-relaxed text-[var(--color-mist)]">
                    Zero tracking. Zero ads. Messages never leave your device. The only server data is a username to ensure no duplicates.
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

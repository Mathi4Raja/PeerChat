'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';

const releases = [
  {
    version: 'v1.0.0',
    date: 'April 20, 2026',
    tag: 'Final Release',
    changes: [
      'Initial production launch of PeerChat.',
      'Full P2P mesh messaging via BLE and WiFi.',
      'End-to-end encryption for all messages and file transfers.',
      'Cross-platform support (Android, Windows, Linux, macOS).',
      'Material 3 design system with custom branding.',
    ]
  },
  {
    version: 'v0.9.5',
    date: 'April 15, 2026',
    tag: 'Beta',
    changes: [
      'Optimized mesh routing performance.',
      'Added high-speed file transfer protocol.',
      'Implemented Google OAuth for unique usernames.',
      'Improved battery life during discovery.',
    ]
  },
  {
    version: 'v0.9.0',
    date: 'April 5, 2026',
    tag: 'Early Access',
    changes: [
      'Core P2P engine stabilization.',
      'Basic chat and file share functionality.',
      'Initial UI/UX prototyping.',
    ]
  }
];

function ReleaseRow({ release, isFirst }: { release: typeof releases[0]; isFirst: boolean }) {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-[160px_1fr] gap-4 lg:gap-12 relative group">
      {/* Sidebar: Sticky Version */}
      <div className="lg:sticky lg:top-12 self-start pt-1">
        <div className="flex items-center gap-3 lg:flex-col lg:items-start lg:gap-1">
          <span className="font-[family-name:var(--font-display)] font-black text-2xl lg:text-3xl text-[var(--color-ivory)] group-hover:text-[var(--color-ember)] transition-colors">
            {release.version}
          </span>
          <div className="flex flex-col">
            <span className="text-[10px] font-[family-name:var(--font-mono)] font-bold text-[var(--color-ash)] uppercase tracking-widest">
              {release.date}
            </span>
            <span className="text-[9px] font-[family-name:var(--font-mono)] text-[var(--color-ember)]/80 uppercase font-bold">
              {release.tag}
            </span>
          </div>
        </div>
      </div>

      {/* Main Content: Flat list */}
      <div className="pb-16 lg:pb-24">
        <ul className="space-y-4">
          {release.changes.map((change, idx) => (
            <motion.li 
              key={idx}
              initial={{ opacity: 0, x: 10 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              transition={{ delay: idx * 0.05 }}
              className="flex items-start gap-4 text-sm leading-relaxed text-[var(--color-mist)]"
            >
              <div className="mt-2.5 w-1.5 h-1.5 rounded-full bg-[var(--color-slate)] shrink-0 group-hover:bg-[var(--color-ember)] transition-colors" />
              <span>{change}</span>
            </motion.li>
          ))}
        </ul>
      </div>
    </div>
  );
}

export default function ChangelogPage() {
  return (
    <div className="min-h-screen bg-[var(--color-ink)] text-[var(--color-mist)] flex flex-col">
      {/* Background Decor */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div className="absolute top-[-10%] right-[-10%] w-[50%] h-[50%] bg-[var(--color-ember)]/5 blur-[120px] rounded-full" />
      </div>

      <main className="max-w-5xl mx-auto px-6 pt-16 flex-1 w-full">
        <header className="mb-16">
          <motion.p 
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
            className="text-[10px] font-[family-name:var(--font-mono)] font-bold text-[var(--color-ember)] uppercase tracking-[0.25em] mb-4"
          >
            Evolution
          </motion.p>
          <motion.h1 
            initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
            className="font-[family-name:var(--font-display)] font-black text-4xl lg:text-6xl text-[var(--color-ivory)] tracking-tight"
          >
            Changelog
          </motion.h1>
        </header>

        <div className="relative">
          {releases.map((rel, i) => (
            <ReleaseRow key={rel.version} release={rel} isFirst={i === 0} />
          ))}
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

'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';

interface SubPageLayoutProps {
  children: React.ReactNode;
  title: string;
  subtitle?: string;
  badge?: string;
}

export default function SubPageLayout({ children, title, subtitle, badge }: SubPageLayoutProps) {
  return (
    <div className="min-h-screen bg-[var(--color-ink)] text-[var(--color-mist)] flex flex-col" style={{ position: 'relative' }}>
      {/* Ambient gradient */}
      <div
        className="fixed top-0 left-0 right-0 h-[440px] pointer-events-none"
        style={{
          background: 'radial-gradient(ellipse 80% 55% at 50% -5%, rgba(139,92,246,0.08) 0%, transparent 70%)',
        }}
      />

      {/* Hero header - moved up (pt-12) */}
      <header className="relative z-10 max-w-5xl mx-auto w-full px-6 pt-12 pb-7 border-b border-[var(--color-slate)]/15">
        {badge && (
          <motion.p
            className="text-[10px] font-[family-name:var(--font-mono)] font-semibold text-[var(--color-ember)] uppercase tracking-[0.2em] mb-2"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4 }}
          >
            {badge}
          </motion.p>
        )}
        <motion.h1
          className="font-[family-name:var(--font-display)] font-black text-[var(--color-ivory)] mb-3"
          style={{ fontSize: 'clamp(1.6rem, 4vw, 2.4rem)', lineHeight: 1.1, letterSpacing: '-0.03em' }}
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
        >
          {title}
        </motion.h1>
        {subtitle && (
          <motion.p
            className="text-[var(--color-ash)] text-sm sm:text-base leading-relaxed max-w-lg"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.6, delay: 0.15 }}
          >
            {subtitle}
          </motion.p>
        )}
      </header>

      {/* Content */}
      <main className="relative z-10 max-w-5xl mx-auto w-full px-6 py-10 pb-16 flex-1">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.2 }}
        >
          {children}
        </motion.div>
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

'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';

import { useEffect, useState } from 'react';

function ReleaseRow({ release, isFirst, isLast }: { release: any; isFirst: boolean; isLast: boolean }) {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-[140px_1fr] gap-4 lg:gap-16 relative group">
      {/* Timeline connector */}
      {!isLast && (
        <div className="absolute top-10 bottom-0 left-[12px] lg:left-[158px] w-[1px] bg-gradient-to-b from-[var(--color-ember)]/30 to-transparent pointer-events-none" />
      )}

      {/* Sidebar: Sticky Version */}
      <div className="sticky top-0 lg:top-24 self-start pt-4 lg:pt-1 z-20 -mx-4 px-4 lg:mx-0 lg:px-0 backdrop-blur-md bg-[var(--color-ink)]/80 lg:bg-transparent lg:backdrop-blur-none transition-all duration-300">
        <div className="flex items-center gap-3 lg:flex-col lg:items-end lg:text-right lg:gap-1 pl-2 lg:pl-0 pb-4 lg:pb-0">
          {/* Timeline Dot (Mobile) */}
          <div className="w-2 h-2 rounded-full bg-[var(--color-ember)]/60 shadow-[0_0_8px_rgba(139,92,246,0.3)] lg:hidden" />
          
          {/* Timeline Dot (Desktop) */}
          <div className="absolute left-[158px] -translate-x-1/2 w-3 h-3 rounded-full border-2 border-[var(--color-ink)] bg-[var(--color-slate)] group-hover:bg-[var(--color-ember)] group-hover:shadow-[0_0_12px_rgba(139,92,246,0.6)] transition-all duration-500 hidden lg:block" />
          
          <span className="font-[family-name:var(--font-display)] font-black text-xl lg:text-4xl text-[var(--color-ivory)] group-hover:text-[var(--color-ember)] transition-colors tracking-tighter">
            {release.version}
          </span>
          <div className="flex flex-row lg:flex-col gap-2 lg:gap-0 items-center lg:items-end">
            <span className="text-[9px] font-[family-name:var(--font-mono)] font-bold text-[var(--color-ash)] uppercase tracking-widest">
              {release.date}
            </span>
            <span className="hidden lg:block text-[9px] font-[family-name:var(--font-mono)] text-[var(--color-ember)]/80 uppercase font-bold tracking-tight">
              {release.tag}
            </span>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="pb-12 lg:pb-24 pl-7 lg:pl-0">
        <div className="bg-[var(--color-charcoal)]/20 border border-[var(--color-slate)]/5 rounded-2xl p-5 sm:p-8 backdrop-blur-sm group-hover:border-[var(--color-ember)]/15 transition-all duration-500">
          <ul className="space-y-3 sm:space-y-4">
            {release.changes.map((change: string, idx: number) => (
              <motion.li 
                key={idx}
                initial={{ opacity: 0, x: 10 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ delay: idx * 0.05 }}
                className="flex items-start gap-3 sm:gap-4 text-xs sm:text-base leading-relaxed text-[var(--color-mist)]"
              >
                <div className="mt-2 w-1 h-1 rounded-full bg-[var(--color-ember)]/40 shrink-0" />
                <span className="opacity-80 group-hover:opacity-100 transition-opacity">{change}</span>
              </motion.li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

export default function ChangelogPage() {
  const [releases, setReleases] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/changelog')
      .then(res => res.json())
      .then(data => {
        if (Array.isArray(data)) {
          setReleases(data);
        }
        setLoading(false);
      })
      .catch(err => {
        console.error('Error fetching changelog:', err);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--color-ink)] flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-[var(--color-ember)] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }
  return (
    <div className="min-h-screen bg-[var(--color-ink)] text-[var(--color-mist)] flex flex-col">
      {/* Background Decor */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div className="absolute top-[-10%] right-[-10%] w-[60%] h-[60%] bg-[var(--color-ember)]/[0.02] blur-[140px] rounded-full" />
        <div className="absolute bottom-[-10%] left-[-10%] w-[40%] h-[40%] bg-[var(--color-copper)]/[0.01] blur-[120px] rounded-full" />
      </div>

      <main className="max-w-4xl mx-auto px-6 pt-8 pb-20 flex-1 w-full relative z-10">
        {/* Top Navigation */}
        <nav className="flex justify-between items-center mb-4">
          <Link href="/" className="group flex items-center gap-2 px-3 py-1.5 rounded-full bg-[var(--color-charcoal)]/40 border border-[var(--color-slate)]/10 hover:border-[var(--color-ember)]/30 transition-all">
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" className="text-[var(--color-ash)] group-hover:text-[var(--color-ember)] transition-colors"><path d="M7.5 2L3.5 6L7.5 10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>
            <span className="text-[10px] font-[family-name:var(--font-mono)] font-bold uppercase tracking-widest text-[var(--color-ash)] group-hover:text-[var(--color-ivory)] transition-colors">Home</span>
          </Link>
          <div className="hidden sm:block h-[1px] flex-1 mx-8 bg-gradient-to-r from-transparent via-[var(--color-slate)]/10 to-transparent" />
        </nav>

        <header className="mb-10 text-center">
          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
            className="inline-flex items-center gap-4 mb-4"
          >
            <div className="w-3 h-[1px] bg-[var(--color-ember)]/30" />
            <span className="text-[12px] sm:text-[13px] font-[family-name:var(--font-mono)] font-bold text-[var(--color-ember)] uppercase tracking-[0.8em]">
              Evolution
            </span>
            <div className="w-3 h-[1px] bg-[var(--color-ember)]/30" />
          </motion.div>
          <motion.h1 
            initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
            className="font-[family-name:var(--font-display)] font-black text-2xl lg:text-5xl text-[var(--color-ivory)] tracking-tight mb-3"
          >
            Changelog
          </motion.h1>
          <motion.p
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.2 }}
            className="text-[var(--color-ash)] text-[10px] sm:text-xs max-w-xs mx-auto opacity-60"
          >
            The growth of a decentralized network.
          </motion.p>
        </header>

        <div className="relative">
          {releases.map((rel, i) => (
            <ReleaseRow 
              key={rel.version} 
              release={rel} 
              isFirst={i === 0} 
              isLast={i === releases.length - 1} 
            />
          ))}
        </div>

        {/* Brand Tagline */}
        <footer className="mt-24 mb-12 text-center">
          <div className="flex items-center justify-center gap-4 mb-4">
            <div className="w-8 h-[1px] bg-gradient-to-r from-transparent to-[var(--color-slate)]/20" />
            <div className="w-1.5 h-1.5 rounded-full bg-[var(--color-slate)]/20" />
            <div className="w-8 h-[1px] bg-gradient-to-l from-transparent to-[var(--color-slate)]/20" />
          </div>
          <p className="font-[family-name:var(--font-mono)] text-[11px] sm:text-[12px] uppercase tracking-[0.5em] text-[var(--color-ember)] font-bold" style={{ textShadow: '0 0 15px rgba(139, 92, 246, 0.3)' }}>
            "The network is the people."
          </p>
        </footer>
      </main>

      {/* Floating Scroll to Top */}
      <motion.button
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 1 }}
        onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
        className="fixed bottom-8 left-8 z-[100] w-12 h-12 rounded-full bg-[var(--color-ink)] border border-[var(--color-ember)]/40 flex items-center justify-center backdrop-blur-md shadow-[0_0_20px_rgba(139,92,246,0.15)] hover:shadow-[0_0_25px_rgba(139,92,246,0.3)] hover:border-[var(--color-ember)] transition-all group"
      >
        <svg width="20" height="20" viewBox="0 0 16 16" fill="none" className="text-[var(--color-ember)] group-hover:-translate-y-0.5 duration-300">
          <path d="M12 10L8 6L4 10" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </motion.button>
    </div>
  );
}

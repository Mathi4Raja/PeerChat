'use client';

import { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { motion, AnimatePresence } from 'framer-motion';
import SubPageLayout from '@/components/SubPageLayout';

export default function DonatePage() {
  const [copied, setCopied] = useState(false);
  const upiId = 'mathi4raja@okaxis';

  const handleCopy = () => {
    navigator.clipboard.writeText(upiId);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <SubPageLayout
      title="Support the Mesh"
      subtitle="PeerChat is free and open-source. Your contributions directly fund privacy research and mesh infrastructure."
      badge="Contributions"
    >
      {/* Unified Support Hub */}
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="relative rounded-[2rem] border border-[var(--color-slate)]/30 bg-[var(--color-charcoal)]/40 backdrop-blur-md p-8 lg:p-10 overflow-hidden mb-10"
        style={{ background: 'linear-gradient(145deg, rgba(24,22,38,0.4) 0%, rgba(15,14,24,0.6) 100%)' }}
      >
        <div className="absolute top-0 right-0 w-64 h-64 bg-[var(--color-ember)]/5 blur-[100px] -mr-32 -mt-32" />
        
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_auto_1fr] gap-10 items-center relative z-10">
          
          {/* Global Support: Ko-fi */}
          <div className="flex flex-col h-full relative z-10">
            <div className="flex items-center gap-4 mb-6">
              <div className="w-10 h-10 rounded-xl bg-[var(--color-ember)]/10 flex items-center justify-center text-[var(--color-ember)] border border-[var(--color-ember)]/20">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 8h1a4 4 0 0 1 0 8h-1"/><path d="M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z"/></svg>
              </div>
              <h3 className="font-[family-name:var(--font-display)] font-bold text-xl text-[var(--color-ivory)]">Global Support</h3>
            </div>
            <p className="text-sm text-[var(--color-ash)] leading-relaxed mb-8 flex-1">
              Perfect for international supporters. Securely contribute via Ko-fi using Card, PayPal, or Apple Pay.
            </p>
            <Link href="https://ko-fi.com/mathi4raja" target="_blank" 
              className="w-full flex items-center justify-center gap-2 bg-[var(--color-ember)] hover:bg-[var(--color-ember)]/90 text-white text-sm font-black py-4 px-6 rounded-2xl transition-all shadow-md shadow-[var(--color-ember)]/5 active:scale-[0.98] relative z-20"
            >
              Donate via Ko-fi
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M7 17l10-10M7 7h10v10"/></svg>
            </Link>
          </div>

          {/* Divider (Desktop Only) */}
          <div className="hidden lg:block w-px h-40 bg-gradient-to-b from-transparent via-[var(--color-slate)]/20 to-transparent" />
          <div className="lg:hidden h-px w-full bg-gradient-to-r from-transparent via-[var(--color-slate)]/20 to-transparent" />

          {/* Local Support: UPI */}
          <div className="flex flex-col sm:flex-row gap-8 items-center">
            <div className="w-40 h-40 bg-white rounded-2xl flex items-center justify-center overflow-hidden border border-white/20 p-3 shadow-2xl shrink-0 group">
              <Image 
                src={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(`upi://pay?pa=${upiId}&pn=Mathi4Raja&cu=INR`)}`}
                alt="UPI QR Code" 
                width={140} 
                height={140} 
                className="w-full h-full object-contain"
                unoptimized
              />
            </div>
            <div className="flex-1 text-center sm:text-left">
              <p className="text-[10px] font-[family-name:var(--font-mono)] text-[var(--color-ash)] uppercase tracking-widest mb-1">Direct (India)</p>
              <h3 className="font-[family-name:var(--font-display)] font-bold text-xl text-[var(--color-ivory)] mb-4">UPI Transfer</h3>
              <code className="text-sm font-bold text-[var(--color-ash)] block mb-5 bg-white/5 py-2 px-3 rounded-lg border border-white/5">{upiId}</code>
              <button 
                onClick={handleCopy}
                className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-widest text-[var(--color-ember)] hover:text-[var(--color-mist)] transition-colors py-2 px-4 rounded-xl bg-[var(--color-ember)]/5 border border-[var(--color-ember)]/10"
              >
                <AnimatePresence mode="wait">
                  {copied ? (
                    <motion.span key="copied" initial={{ opacity: 0, scale: 0.8 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }}>Copied!</motion.span>
                  ) : (
                    <motion.span key="copy" initial={{ opacity: 0, scale: 0.8 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }} className="flex items-center gap-2">
                      <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/></svg>
                      Copy UPI ID
                    </motion.span>
                  )}
                </AnimatePresence>
              </button>
            </div>
          </div>
        </div>
      </motion.div>

      {/* Compact Funds Info */}
      <motion.div
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 1 }}
        viewport={{ once: true }}
        className="rounded-[2rem] border border-[var(--color-slate)]/20 bg-gradient-to-b from-[var(--color-charcoal)]/30 to-transparent p-8 lg:p-10"
      >
        <h2 className="font-[family-name:var(--font-display)] font-black text-xl text-[var(--color-ivory)] mb-8 flex items-center gap-3">
          <span className="w-1.5 h-6 bg-[var(--color-ember)] rounded-full" />
          Where your support goes
        </h2>
        
        <ul className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
          {[
            { 
              title: 'Mesh R&D', 
              desc: 'Routing research & mesh reliability.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 2v8m0 4v8m-10-10h8"/></svg>
            },
            { 
              title: 'Open Source', 
              desc: 'Keeping PeerChat free & auditable.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 12m-9 0a9 9 0 1 0 18 0"/></svg>
            },
            { 
              title: 'Security', 
              desc: 'Cryptographic protocol reviews.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            },
            { 
              title: 'Infrastructure', 
              desc: 'Update servers & domain costs.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M4 11a9 9 0 0 1 9 9m-9-13a13 13 0 0 1 13 13"/></svg>
            },
          ].map((item, idx) => (
            <li key={idx} className="group">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-8 h-8 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-[var(--color-ember)] group-hover:bg-[var(--color-ember)]/10 transition-all">
                  {item.icon}
                </div>
                <h4 className="font-bold text-[var(--color-ivory)] text-sm">{item.title}</h4>
              </div>
              <p className="text-[11px] text-[var(--color-ash)] leading-relaxed">
                {item.desc}
              </p>
            </li>
          ))}
        </ul>
      </motion.div>
    </SubPageLayout>
  );
}

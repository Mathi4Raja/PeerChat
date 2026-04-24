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
      subtitle="PeerChat is built by the community, for the community. Your contributions help keep our network independent and private."
      badge="Contributions"
    >
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-12">
        {/* Ko-fi Card */}
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="relative rounded-2xl border border-[var(--color-slate)]/30 bg-[var(--color-charcoal)]/40 backdrop-blur-sm p-8 flex flex-col group overflow-hidden"
          style={{ background: 'linear-gradient(145deg, rgba(24,22,38,0.4) 0%, rgba(15,14,24,0.6) 100%)' }}
        >
          <div className="absolute top-0 right-0 w-32 h-32 bg-[var(--color-ember)]/5 blur-3xl -mr-16 -mt-16 group-hover:bg-[var(--color-ember)]/10 transition-colors" />
          
          <div className="flex items-center gap-5 mb-8">
            <div className="w-14 h-14 rounded-2xl bg-[var(--color-ember)]/10 flex items-center justify-center text-[var(--color-ember)] border border-[var(--color-ember)]/20">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M18 8h1a4 4 0 0 1 0 8h-1"/><path d="M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z"/><line x1="6" y1="1" x2="6" y2="4"/><line x1="10" y1="1" x2="10" y2="4"/><line x1="14" y1="1" x2="14" y2="4"/></svg>
            </div>
            <div>
              <h3 className="font-[family-name:var(--font-display)] font-bold text-xl text-[var(--color-ivory)]">Buy us a coffee</h3>
              <p className="text-xs text-[var(--color-ash)] font-[family-name:var(--font-mono)] uppercase tracking-wider">Via Ko-fi Global</p>
            </div>
          </div>

          <p className="text-sm text-[var(--color-ash)] leading-relaxed mb-8 flex-1">
            The easiest way to support us from anywhere in the world. Help us cover server costs and domain renewals.
          </p>

          <Link href="https://ko-fi.com/mathi4raja" target="_blank" 
            className="w-full flex items-center justify-center gap-2 bg-[var(--color-ember)] hover:bg-[var(--color-ember)]/90 text-white text-sm font-black py-4 px-6 rounded-xl transition-all shadow-lg shadow-[var(--color-ember)]/10 hover:shadow-[var(--color-ember)]/20 active:scale-[0.98]"
          >
            Donate with Ko-fi
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M7 17l10-10M7 7h10v10"/></svg>
          </Link>
        </motion.div>

        {/* UPI Card */}
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="relative rounded-2xl border border-[var(--color-slate)]/30 bg-[var(--color-charcoal)]/40 backdrop-blur-sm p-8 flex flex-col group overflow-hidden"
          style={{ background: 'linear-gradient(145deg, rgba(24,22,38,0.4) 0%, rgba(15,14,24,0.6) 100%)' }}
        >
          <div className="flex items-center gap-5 mb-6">
            <div className="w-14 h-14 rounded-2xl bg-[var(--color-ember)]/10 flex items-center justify-center text-[var(--color-ember)] border border-[var(--color-ember)]/20">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/></svg>
            </div>
            <div>
              <h3 className="font-[family-name:var(--font-display)] font-bold text-xl text-[var(--color-ivory)]">UPI Transfer</h3>
              <p className="text-xs text-[var(--color-ash)] font-[family-name:var(--font-mono)] uppercase tracking-wider">Direct (India Only)</p>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row gap-6 items-center bg-white/5 border border-white/10 rounded-2xl p-6 mb-4">
             <div className="w-40 h-40 bg-white rounded-2xl flex items-center justify-center overflow-hidden border border-white/20 p-3 shadow-xl shrink-0">
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
                <p className="text-[10px] font-[family-name:var(--font-mono)] text-[var(--color-ash)] uppercase tracking-widest mb-1">UPI ID</p>
                <code className="text-base font-bold text-[var(--color-ivory)] block mb-4">{upiId}</code>
                <button 
                  onClick={handleCopy}
                  className="inline-flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-[var(--color-ember)] hover:text-[var(--color-mist)] transition-colors py-2 px-4 rounded-lg bg-[var(--color-ember)]/5 border border-[var(--color-ember)]/10"
                >
                  <AnimatePresence mode="wait">
                    {copied ? (
                      <motion.span key="copied" initial={{ opacity: 0, scale: 0.8 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }}>Copied!</motion.span>
                    ) : (
                      <motion.span key="copy" initial={{ opacity: 0, scale: 0.8 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }} className="flex items-center gap-2">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/></svg>
                        Copy UPI ID
                      </motion.span>
                    )}
                  </AnimatePresence>
                </button>
             </div>
          </div>
        </motion.div>
      </div>

      {/* Funds Info */}
      <motion.div
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 1 }}
        viewport={{ once: true }}
        className="rounded-3xl border border-[var(--color-slate)]/20 bg-gradient-to-b from-[var(--color-charcoal)]/30 to-transparent p-6 lg:p-8"
      >
        <h2 className="font-[family-name:var(--font-display)] font-black text-xl text-[var(--color-ivory)] mb-6 flex items-center gap-3">
          <span className="w-1 h-6 bg-[var(--color-ember)] rounded-full" />
          Where your support goes
        </h2>
        
        <ul className="grid grid-cols-1 md:grid-cols-2 gap-x-10 gap-y-6">
          {[
            { 
              title: 'Mesh R&D', 
              desc: 'Multi-hop routing research and building store-and-forward reliability.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 2v8m0 4v8m-10-10h8m4 0h8m-13.5-6.5l3 3m4 4l3 3m0-10l-3 3m-4 4l-3 3"/></svg>
            },
            { 
              title: 'Open Source', 
              desc: 'Keeping PeerChat free, auditable, and zero-ads — forever.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0"/><path d="M12 12l3 3m-3-3l-3 3m3-3l3-3m-3 3l-3-3"/></svg>
            },
            { 
              title: 'Security Audits', 
              desc: 'Independent cryptographic protocol reviews to ensure absolute privacy.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            },
            { 
              title: 'Infrastructure', 
              desc: 'High-speed update servers and domain maintenance.',
              icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M4 11a9 9 0 0 1 9 9m-9-13a13 13 0 0 1 13 13m-13-17a17 17 0 0 1 17 17"/></svg>
            },
          ].map((item, idx) => (
            <li key={idx} className="group">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-8 h-8 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-[var(--color-ember)] group-hover:bg-[var(--color-ember)]/10 group-hover:border-[var(--color-ember)]/20 transition-all">
                  {item.icon}
                </div>
                <h4 className="font-bold text-[var(--color-ivory)] text-base">{item.title}</h4>
              </div>
              <p className="text-xs text-[var(--color-ash)] leading-relaxed pl-11">
                {item.desc}
              </p>
            </li>
          ))}
        </ul>
      </motion.div>
    </SubPageLayout>
  );
}

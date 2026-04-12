'use client';

import { motion, useInView, AnimatePresence } from 'framer-motion';
import { useRef, useState } from 'react';

const FAQS = [
  {
    question: "What exactly is PeerChat?",
    answer: "PeerChat is a decentralized, serverless communication platform. It allows users to send encrypted messages and files directly between devices by forming a temporary or stable mesh network using Bluetooth and WiFi."
  },
  {
    question: "How does it work without internet?",
    answer: "PeerChat turns your device into a node in a mesh network. It uses BLE (Bluetooth Low Energy) for discovery and small data packets, and WiFi Direct or WiFi Hotspot for high-speed file transfers. If people are in range, they can communicate directly without any cellular towers or ISP."
  },
  {
    question: "Is my data secure?",
    answer: "Yes. Every message is end-to-end encrypted (E2EE) and digitally signed using Sodium (libsodium). Only the recipient possesses the private key required to decrypt and read your messages. No central server ever sees your data because there is no central server."
  },
  {
    question: "How does multi-hop mesh routing work?",
    answer: "If you want to message someone who is too far away to reach via Bluetooth directly, PeerChat can automatically 'hop' the message through intermediate devices (peers) until it reaches the destination. Each hop is encrypted, so intermediate peers cannot read your message."
  },
  {
    question: "Is PeerChat open source?",
    answer: "Yes. We believe privacy tools must be transparent. PeerChat's protocol and application source code are open for public audit and contribution on GitHub."
  },
  {
    question: "What are the hardware requirements?",
    answer: "Currently, PeerChat is optimized for Android devices with Bluetooth 4.2+ and WiFi capabilities. It works across a wide range of devices from legacy phones to modern flagships."
  }
];

export default function FaqSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.2 });
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  return (
    <section ref={ref} className="px-4 sm:px-6 py-20 sm:py-32 bg-[var(--color-ink)]" id="faq">
      <div className="max-w-3xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8 }}
          className="text-center mb-16"
        >
          <span className="mono-label text-[var(--color-ember)] mb-4 block">07 — FAQ</span>
          <h2 className="display-heading text-3xl sm:text-4xl md:text-5xl lg:text-6xl text-[var(--color-ivory)]">
            Common <span className="gradient-text-ember">Questions.</span>
          </h2>
        </motion.div>

        <div className="space-y-4">
          {FAQS.map((faq, i) => {
            const isOpen = activeIndex === i;
            return (
              <motion.div
                key={i}
                initial={{ opacity: 0, y: 10 }}
                animate={isInView ? { opacity: 1, y: 0 } : {}}
                transition={{ delay: i * 0.1, duration: 0.5 }}
                className="overflow-hidden"
              >
                <button
                  onClick={() => setActiveIndex(isOpen ? null : i)}
                  className={`w-full text-left p-6 rounded-2xl border transition-all duration-300 flex justify-between items-center group
                    ${isOpen ? 'bg-[var(--color-charcoal)] border-[var(--color-ember)]/50' : 'bg-transparent border-[var(--color-slate)]/20 hover:border-[var(--color-slate)]/40'}
                  `}
                >
                  <span className={`font-[family-name:var(--font-display)] font-semibold text-lg sm:text-xl transition-colors
                    ${isOpen ? 'text-[var(--color-ivory)]' : 'text-[var(--color-ash)] group-hover:text-[var(--color-ivory)]'}
                  `}>
                    {faq.question}
                  </span>
                  <div className={`w-6 h-6 rounded-full border border-[var(--color-slate)]/30 flex items-center justify-center transition-transform duration-300 ${isOpen ? 'rotate-180 border-[var(--color-ember)]/50' : ''}`}>
                    <svg width="10" height="6" viewBox="0 0 10 6" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <path d="M1 1L5 5L9 1" stroke={isOpen ? 'var(--color-ember)' : 'currentColor'} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
                    </svg>
                  </div>
                </button>
                <AnimatePresence>
                  {isOpen && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.3, ease: "easeInOut" }}
                    >
                      <div className="p-6 pt-2 text-[var(--color-ash)] leading-relaxed text-sm sm:text-base border-x border-b border-[var(--color-ember)]/10 rounded-b-2xl -mt-2 bg-[var(--color-charcoal)]/30">
                        {faq.answer}
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

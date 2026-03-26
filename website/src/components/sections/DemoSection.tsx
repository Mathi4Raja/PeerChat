'use client';

import { useRef, useState, useEffect } from 'react';
import { motion, useInView, useScroll, useMotionValueEvent, AnimatePresence } from 'framer-motion';

interface ChatMessage {
  id: number;
  text: string;
  sender: 'incoming' | 'outgoing';
  hops: number;
  encrypted: string;
}

const conversation: ChatMessage[] = [
  {
    id: 1,
    text: 'Are you safe?',
    sender: 'outgoing',
    hops: 3,
    encrypted: '0xA3F1…9B2E',
  },
  {
    id: 2,
    text: 'Yes. We made it to the shelter. Power is out everywhere.',
    sender: 'incoming',
    hops: 5,
    encrypted: '0x7B2E…D4C8',
  },
  {
    id: 3,
    text: 'Sending medical supplies to Block 7. ETA 20 minutes.',
    sender: 'outgoing',
    hops: 4,
    encrypted: '0xD4C8…91FA',
  },
  {
    id: 4,
    text: 'Copy. We have 12 people here. Bring water too.',
    sender: 'incoming',
    hops: 6,
    encrypted: '0x91FA…3E7B',
  },
];

function SignalPath({ hops, visible }: { hops: number; visible: boolean }) {
  return (
    <div className="flex items-center gap-1 my-2">
      {Array.from({ length: hops }).map((_, i) => (
        <motion.div
          key={i}
          className="flex items-center gap-1"
          initial={{ opacity: 0 }}
          animate={visible ? { opacity: 1 } : {}}
          transition={{ delay: i * 0.1, duration: 0.3 }}
        >
          <div
            className="w-1.5 h-1.5 rounded-full"
            style={{
              background: i === 0 ? 'var(--color-ember)' : i === hops - 1 ? 'var(--color-sage)' : 'var(--color-copper)',
              boxShadow: `0 0 4px ${i === 0 ? 'rgba(139,92,246,0.5)' : i === hops - 1 ? 'rgba(99,102,241,0.5)' : 'rgba(167,139,250,0.3)'}`,
            }}
          />
          {i < hops - 1 && (
            <motion.div
              className="w-4 h-[1px] bg-[var(--color-slate)]"
              initial={{ scaleX: 0 }}
              animate={visible ? { scaleX: 1 } : {}}
              transition={{ delay: i * 0.1 + 0.05, duration: 0.2 }}
              style={{ transformOrigin: 'left' }}
            />
          )}
        </motion.div>
      ))}
      <span className="ml-2 font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-ash)]">
        {hops} hops
      </span>
    </div>
  );
}

export default function DemoSection() {
  const ref = useRef<HTMLDivElement>(null);
  const stickyRef = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.1 });
  const [visibleMessages, setVisibleMessages] = useState<number[]>([]);
  const [showEncryption, setShowEncryption] = useState<number | null>(null);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const check = () => setIsMobile(window.innerWidth < 1024);
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  const vhPerStep = isMobile ? 55 : 100;

  // Scroll-driven message reveal pinned to the tall wrapper
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start start', 'end end'],
  });

  useMotionValueEvent(scrollYProgress, 'change', (progress) => {
    // Messages appear between 10% and 85% scroll through the tall container
    const msgCount = conversation.length;
    const startThreshold = 0.1;
    const endThreshold = 0.85;
    const range = endThreshold - startThreshold;

    const shouldShow = Math.floor(
      Math.min(msgCount, Math.max(0, ((progress - startThreshold) / range) * (msgCount + 1)))
    );

    const newVisible = conversation.slice(0, shouldShow).map((m) => m.id);
    setVisibleMessages((prev) => {
      if (prev.length === newVisible.length) return prev;
      return newVisible;
    });
  });

  /* Shared text content */
  const textContent = (
    <>
      <motion.div
        initial={{ opacity: 0 }}
        animate={isInView ? { opacity: 1 } : {}}
        transition={{ duration: 0.8 }}
        className="mb-4 sm:mb-12"
      >
        <span className="mono-label text-[var(--color-sage)]">
          05 — Real World
        </span>
      </motion.div>

      <motion.h2
        className="display-heading text-2xl sm:text-3xl md:text-5xl mb-4 sm:mb-6"
        initial={{ opacity: 0, y: 30 }}
        animate={isInView ? { opacity: 1, y: 0 } : {}}
        transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
      >
        <span className="text-[var(--color-ivory)]">Signals become</span>{' '}
        <span className="gradient-text-warm">conversations.</span>
      </motion.h2>

      <motion.p
        className="text-sm sm:text-base text-[var(--color-ash)] leading-relaxed mb-6 sm:mb-8"
        initial={{ opacity: 0 }}
        animate={isInView ? { opacity: 1 } : {}}
        transition={{ duration: 0.8, delay: 0.4 }}
      >
        Each message travels through the mesh as an encrypted signal.
        Relay devices carry ciphertext they can never read.
        Only the recipient can decrypt.
      </motion.p>

      <motion.div
        className="flex items-center gap-3 text-sm text-[var(--color-ash)]"
        initial={{ opacity: 0 }}
        animate={isInView ? { opacity: 1 } : {}}
        transition={{ duration: 0.8, delay: 0.6 }}
      >
        <div className="w-2 h-2 rounded-full bg-[var(--color-sage)]" style={{ boxShadow: '0 0 8px rgba(99,102,241,0.5)' }} />
        <span>End-to-end encrypted with libsodium</span>
      </motion.div>
    </>
  );

  /* Shared chat UI */
  const chatUI = (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={isInView ? { opacity: 1, y: 0 } : {}}
      transition={{ duration: 1, delay: 0.3 }}
      className="relative"
    >
      {/* Phone frame */}
      <div className="relative mx-auto max-w-sm rounded-3xl border border-[var(--color-slate)] bg-[var(--color-charcoal)] p-1 overflow-hidden">
        {/* Status bar */}
        <div className="px-5 py-3 flex items-center justify-between border-b border-[var(--color-slate)]/50">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-[var(--color-sage)]" />
            <span className="font-[family-name:var(--font-mono)] text-xs text-[var(--color-ash)]">
              mesh://peer-47a3
            </span>
          </div>
          <span className="font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-slate)]">
            E2E
          </span>
        </div>

        {/* Messages */}
        <div className="px-3 sm:px-4 py-3 sm:py-4 space-y-3 min-h-[280px] sm:min-h-[380px]">
          <AnimatePresence>
            {conversation
              .filter(msg => visibleMessages.includes(msg.id))
              .map(msg => (
                <motion.div
                  key={msg.id}
                  initial={{ opacity: 0, y: 12, scale: 0.95 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  transition={{
                    duration: 0.5,
                    ease: [0.16, 1, 0.3, 1],
                  }}
                  className={`flex flex-col ${msg.sender === 'outgoing' ? 'items-end' : 'items-start'}`}
                >
                  <SignalPath hops={msg.hops} visible={true} />
                  <div
                    className={`chat-bubble px-4 py-3 max-w-[280px] text-sm leading-relaxed cursor-pointer ${
                      msg.sender === 'outgoing' ? 'chat-bubble-outgoing' : 'chat-bubble-incoming'
                    }`}
                    onClick={() => setShowEncryption(showEncryption === msg.id ? null : msg.id)}
                  >
                    {showEncryption === msg.id ? (
                      <span className="font-[family-name:var(--font-mono)] text-xs text-[var(--color-copper)] break-all">
                        {msg.encrypted}…{Array.from({length: 20}).map(() => 
                          '0123456789abcdef'[Math.floor(Math.random() * 16)]
                        ).join('')}
                      </span>
                    ) : (
                      <span className="text-[var(--color-mist)]">{msg.text}</span>
                    )}
                  </div>
                  <span className="font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-slate)] mt-1">
                    {showEncryption === msg.id ? 'encrypted payload' : 'tap to view encrypted'}
                  </span>
                </motion.div>
              ))}
          </AnimatePresence>

          {/* Typing indicator */}
          {visibleMessages.length < conversation.length && visibleMessages.length > 0 && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="flex items-center gap-1 pl-2"
            >
              {[0, 1, 2].map(i => (
                <div
                  key={i}
                  className="w-1.5 h-1.5 rounded-full bg-[var(--color-ash)]"
                  style={{
                    animation: `pulse 1.2s ease-in-out ${i * 0.2}s infinite`,
                  }}
                />
              ))}
              <span className="ml-2 font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-slate)]">
                signal propagating...
              </span>
            </motion.div>
          )}
        </div>
      </div>
    </motion.div>
  );

  return (
    <section
      ref={ref}
      className="relative"
      id="demo"
      style={{ height: `${(conversation.length + 1) * vhPerStep}vh` }}
    >
      {/* Mobile: text scrolls away, only chat sticks */}
      <div className="lg:hidden px-4 pt-10 pb-6">
        {textContent}
      </div>

      {/* Sticky area: on mobile = just chat centered, on desktop = full side-by-side */}
      <div
        ref={stickyRef}
        className="sticky top-0 h-[100dvh] flex items-center justify-center px-4 sm:px-6"
      >
        <div className="max-w-5xl mx-auto w-full">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 sm:gap-16 items-center">
            {/* Desktop text — hidden on mobile (shown above instead) */}
            <div className="hidden lg:block">
              {textContent}
            </div>

            {/* Chat demo — always visible inside sticky */}
            {chatUI}
          </div>
        </div>
      </div>
    </section>
  );
}

'use client';

import { useRef, useState, useEffect, useMemo } from 'react';
import { motion, useInView, AnimatePresence } from 'framer-motion';
import { Smartphone, Lock, Unlock, ShieldCheck, Wifi, Bluetooth } from 'lucide-react';

/* ── Relay chain: each node the packet passes through ── */
const RELAYS = [
  { label: 'You', role: 'sender' as const },
  { label: 'Node A', role: 'relay' as const },
  { label: 'Node B', role: 'relay' as const },
  { label: 'Node C', role: 'relay' as const },
  { label: 'Recipient', role: 'receiver' as const },
];

const MESSAGE = 'Are you safe?';

/* ── Generate deterministic "encrypted" gibberish for each relay ── */
function encryptedPayload(seed: number) {
  const chars = '0123456789abcdef';
  let s = '';
  for (let i = 0; i < 16; i++) s += chars[(seed * 7 + i * 13) % 16];
  return `0x${s.slice(0, 4)}…${s.slice(4, 8)}`;
}

export default function MessageFlowSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.25 });
  const [packetAt, setPacketAt] = useState(-1);
  const [delivered, setDelivered] = useState(false);
  const [cycle, setCycle] = useState(0);

  const totalNodes = RELAYS.length;

  /* ── Animation cycle ── */
  useEffect(() => {
    if (!isInView) return;
    const timers: NodeJS.Timeout[] = [];

    setPacketAt(-1);
    setDelivered(false);

    for (let i = 0; i < totalNodes; i++) {
      timers.push(setTimeout(() => setPacketAt(i), 1000 + i * 900));
    }

    timers.push(setTimeout(() => setDelivered(true), 1000 + totalNodes * 900 + 300));
    timers.push(setTimeout(() => setCycle((c) => c + 1), 1000 + totalNodes * 900 + 3500));

    return () => timers.forEach(clearTimeout);
  }, [isInView, cycle, totalNodes]);

  const encStrings = useMemo(() => RELAYS.map((_, i) => encryptedPayload(i + cycle * 5)), [cycle]);

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32"
      id="message-flow"
    >
      <div className="max-w-5xl mx-auto w-full">
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8 }}
          className="mb-5 sm:mb-12"
        >
          <span className="mono-label text-[var(--color-copper)]">
            Signal Path
          </span>
        </motion.div>

        <motion.h2
          className="display-heading text-2xl sm:text-3xl md:text-5xl mb-4 sm:mb-6 max-w-3xl"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
        >
          <span className="text-[var(--color-ivory)]">Watch a message</span>{' '}
          <span className="gradient-text-warm">traverse the mesh.</span>
        </motion.h2>

        <motion.p
          className="text-sm sm:text-base text-[var(--color-ash)] leading-relaxed mb-8 sm:mb-14 max-w-xl"
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8, delay: 0.4 }}
        >
          Every message hops through relay nodes as encrypted ciphertext.
          No single device sees the full path. No relay can read the payload.
        </motion.p>

        {/* ── Relay chain visualization ── */}
        <motion.div
          className="relative rounded-2xl sm:rounded-3xl border border-[var(--color-slate)]/30 overflow-hidden"
          style={{
            background: 'linear-gradient(180deg, rgba(15,14,24,0.6) 0%, rgba(9,9,15,0.8) 100%)',
          }}
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8, delay: 0.5 }}
        >
          <div className="p-3 sm:p-8 md:p-10">
            {/* ── Chain: nodes + connectors ── */}
            <div className="flex items-stretch justify-between gap-0 pb-2">
              {RELAYS.map((relay, i) => {
                const isActive = packetAt >= i;
                const isCurrent = packetAt === i;
                const isSender = relay.role === 'sender';
                const isReceiver = relay.role === 'receiver';
                const showDecrypted = isReceiver && delivered;
                const showOriginal = isSender && packetAt >= 0;

                return (
                  <div key={i} className="flex items-stretch flex-1 min-w-0">
                    {/* ── Node card ── */}
                    <motion.div
                      className="relative flex flex-col items-center flex-shrink-0"
                      style={{ width: 'clamp(44px, 16vw, 100px)' }}
                      initial={{ opacity: 0, y: 20 }}
                      animate={isInView ? { opacity: 1, y: 0 } : {}}
                      transition={{ duration: 0.6, delay: 0.7 + i * 0.12, ease: [0.16, 1, 0.3, 1] }}
                    >
                      {/* Icon container */}
                      <motion.div
                        className="relative w-9 h-9 sm:w-12 sm:h-12 md:w-14 md:h-14 rounded-lg sm:rounded-xl flex items-center justify-center border"
                        animate={{
                          borderColor: isCurrent
                            ? '#8B5CF6'
                            : isActive
                            ? 'rgba(139,92,246,0.3)'
                            : 'rgba(38,36,56,0.6)',
                          background: isCurrent
                            ? 'rgba(139,92,246,0.15)'
                            : 'rgba(15,14,24,0.8)',
                          boxShadow: isCurrent
                            ? '0 0 20px rgba(139,92,246,0.3), 0 0 40px rgba(139,92,246,0.1)'
                            : '0 0 0 transparent',
                        }}
                        transition={{ duration: 0.4 }}
                      >
                        {isSender || isReceiver ? (
                          <Smartphone className="w-3.5 h-3.5 sm:w-5 sm:h-5 md:w-6 md:h-6 text-[var(--color-ivory)]" />
                        ) : (
                          <div className="flex items-center gap-0 sm:gap-0.5">
                            <Wifi className="w-2.5 h-2.5 sm:w-3.5 sm:h-3.5 md:w-4 md:h-4 text-[var(--color-copper)]" />
                            <span className="text-[var(--color-ash)] text-[6px] sm:text-[8px] leading-none">/</span>
                            <Bluetooth className="w-2.5 h-2.5 sm:w-3.5 sm:h-3.5 md:w-4 md:h-4 text-[var(--color-copper)]" />
                          </div>
                        )}

                        {/* Lock badge */}
                        <motion.div
                          className="absolute -bottom-1 -right-1 sm:-bottom-1.5 sm:-right-1.5 w-4 h-4 sm:w-5 sm:h-5 rounded-full flex items-center justify-center"
                          style={{
                            background: 'var(--color-charcoal)',
                            border: `1.5px solid ${showDecrypted ? '#4ade80' : isActive ? '#8B5CF6' : '#262438'}`,
                          }}
                          animate={{
                            scale: isCurrent ? [1, 1.15, 1] : 1,
                          }}
                          transition={{ duration: 0.6, repeat: isCurrent ? Infinity : 0 }}
                        >
                          {showDecrypted ? (
                            <Unlock className="w-2 h-2 sm:w-2.5 sm:h-2.5 text-green-400" />
                          ) : (
                            <Lock className="w-2 h-2 sm:w-2.5 sm:h-2.5" style={{ color: isActive ? '#8B5CF6' : '#262438' }} />
                          )}
                        </motion.div>

                        {/* Pulse ring on current */}
                        <AnimatePresence>
                          {isCurrent && (
                            <motion.div
                              className="absolute inset-0 rounded-lg sm:rounded-xl border border-[var(--color-ember)]"
                              initial={{ scale: 1, opacity: 0.6 }}
                              animate={{ scale: 1.4, opacity: 0 }}
                              exit={{ opacity: 0 }}
                              transition={{ duration: 1.2, repeat: Infinity }}
                            />
                          )}
                        </AnimatePresence>
                      </motion.div>

                      {/* Label */}
                      <motion.span
                        className="mt-1 sm:mt-2 font-[family-name:var(--font-mono)] text-[7px] sm:text-[9px] md:text-[10px] whitespace-nowrap"
                        animate={{ color: isActive ? '#F5F3FF' : '#878599' }}
                        transition={{ duration: 0.3 }}
                      >
                        {relay.label}
                      </motion.span>

                      {/* Payload preview card */}
                      <AnimatePresence mode="wait">
                        {isCurrent && (
                          <motion.div
                            key={`payload-${i}-${cycle}`}
                            className="absolute -bottom-10 sm:-bottom-14 md:-bottom-16 w-16 sm:w-24 md:w-28 rounded-md sm:rounded-lg border px-1 sm:px-2 py-1 sm:py-1.5 text-center"
                            style={{
                              background: 'rgba(15,14,24,0.95)',
                              borderColor: showDecrypted ? 'rgba(74,222,128,0.3)' : 'rgba(139,92,246,0.2)',
                              backdropFilter: 'blur(8px)',
                            }}
                            initial={{ opacity: 0, y: -6, scale: 0.9 }}
                            animate={{ opacity: 1, y: 0, scale: 1 }}
                            exit={{ opacity: 0, y: 4, scale: 0.95 }}
                            transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}
                          >
                            {showDecrypted ? (
                              <span className="text-[7px] sm:text-[9px] md:text-[10px] text-green-400 font-[family-name:var(--font-body)]">
                                {MESSAGE}
                              </span>
                            ) : showOriginal ? (
                              <span className="text-[7px] sm:text-[9px] md:text-[10px] text-[var(--color-mist)] font-[family-name:var(--font-body)]">
                                {MESSAGE}
                              </span>
                            ) : (
                              <span className="text-[6px] sm:text-[8px] md:text-[9px] text-[var(--color-copper)] font-[family-name:var(--font-mono)] break-all">
                                {encStrings[i]}
                              </span>
                            )}
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </motion.div>

                    {/* ── Connector line between nodes ── */}
                    {i < totalNodes - 1 && (
                      <div className="flex-1 flex items-center justify-center relative min-w-[8px] sm:min-w-[20px] self-center" style={{ height: 2, marginTop: '-12px' }}>
                        {/* Background line */}
                        <motion.div
                          className="absolute inset-0 rounded-full"
                          style={{ background: 'var(--color-slate)', opacity: 0.2 }}
                          initial={{ scaleX: 0 }}
                          animate={isInView ? { scaleX: 1 } : {}}
                          transition={{ duration: 0.4, delay: 0.9 + i * 0.12, ease: 'easeOut' }}
                        />
                        {/* Active line */}
                        <motion.div
                          className="absolute inset-0 rounded-full origin-left"
                          style={{
                            background: 'linear-gradient(90deg, #8B5CF6, #A78BFA)',
                          }}
                          initial={{ scaleX: 0, opacity: 0 }}
                          animate={{
                            scaleX: packetAt > i ? 1 : 0,
                            opacity: packetAt > i ? 1 : 0,
                          }}
                          transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
                        />
                        {/* Traveling dot */}
                        <AnimatePresence>
                          {packetAt === i + 1 && (
                            <motion.div
                              className="absolute w-2 h-2 rounded-full bg-white z-10"
                              style={{
                                boxShadow: '0 0 8px rgba(255,255,255,0.8), 0 0 20px rgba(139,92,246,0.5)',
                                top: '-3px',
                              }}
                              initial={{ left: '0%', opacity: 0 }}
                              animate={{ left: '100%', opacity: [0, 1, 1, 0.6] }}
                              transition={{ duration: 0.6, ease: [0.4, 0, 0.2, 1] }}
                            />
                          )}
                        </AnimatePresence>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* ── Bottom status bar ── */}
            <motion.div
              className="mt-12 sm:mt-20 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-2 sm:gap-3 px-0 sm:px-1"
              initial={{ opacity: 0 }}
              animate={isInView ? { opacity: 1 } : {}}
              transition={{ duration: 0.8, delay: 1.2 }}
            >
              {/* Hop progress */}
              <div className="flex items-center gap-1.5">
                {RELAYS.map((_, i) => (
                  <motion.div
                    key={i}
                    className="rounded-full"
                    style={{ width: 5, height: 5 }}
                    animate={{
                      background: packetAt >= i ? '#8B5CF6' : '#262438',
                      boxShadow: packetAt >= i ? '0 0 6px rgba(139,92,246,0.5)' : 'none',
                    }}
                    transition={{ duration: 0.3 }}
                  />
                ))}
                <span className="ml-1.5 font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-ash)]">
                  {packetAt >= 0
                    ? `${Math.min(packetAt + 1, totalNodes)}/${totalNodes} nodes`
                    : 'initializing...'}
                </span>
              </div>

              {/* Encryption info */}
              <div className="flex items-center gap-4">
                <span className="font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-slate)]">
                  NaCl · curve25519
                </span>
                <AnimatePresence mode="wait">
                  {delivered ? (
                    <motion.div
                      key="delivered"
                      className="flex items-center gap-1.5"
                      initial={{ opacity: 0, x: 8 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0 }}
                      transition={{ duration: 0.4 }}
                    >
                      <motion.div
                        className="w-1.5 h-1.5 rounded-full bg-green-400"
                        animate={{ boxShadow: ['0 0 3px #4ade80', '0 0 8px #4ade80', '0 0 3px #4ade80'] }}
                        transition={{ duration: 2, repeat: Infinity }}
                      />
                      <span className="font-[family-name:var(--font-mono)] text-[10px] text-green-400/80">
                        delivered
                      </span>
                      <ShieldCheck className="w-3 h-3 text-green-400/60" />
                    </motion.div>
                  ) : packetAt >= 0 ? (
                    <motion.span
                      key="transit"
                      className="font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-copper)]"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: [0.5, 1, 0.5] }}
                      transition={{ duration: 1.2, repeat: Infinity }}
                    >
                      in transit...
                    </motion.span>
                  ) : (
                    <motion.span
                      key="waiting"
                      className="font-[family-name:var(--font-mono)] text-[10px] text-[var(--color-slate)]"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: [0.3, 0.7, 0.3] }}
                      transition={{ duration: 1.5, repeat: Infinity }}
                    >
                      encrypting...
                    </motion.span>
                  )}
                </AnimatePresence>
              </div>
            </motion.div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}

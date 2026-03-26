'use client';

import { useRef, useState, useEffect, useCallback } from 'react';
import { motion, useInView, AnimatePresence } from 'framer-motion';

/* ── Typewriter hook ── */
function useTypewriter(text: string, active: boolean, speed = 35) {
  const [displayed, setDisplayed] = useState('');
  useEffect(() => {
    if (!active) { setDisplayed(''); return; }
    let i = 0;
    const id = setInterval(() => {
      i++;
      setDisplayed(text.slice(0, i));
      if (i >= text.length) clearInterval(id);
    }, speed);
    return () => clearInterval(id);
  }, [text, active, speed]);
  return displayed;
}

/* ── Hex typewriter sub-component ── */
function HexLabel({ text, active }: { text: string; active: boolean }) {
  const displayed = useTypewriter(text, active, 25);
  return (
    <span className="font-[family-name:var(--font-mono)] text-xs text-[var(--color-slate)] transition-colors duration-500">
      {displayed}
      {active && displayed.length < text.length && (
        <span className="inline-block w-[5px] h-[13px] bg-[var(--color-ember)] ml-[1px] animate-[blink_0.6s_steps(1)_infinite] align-middle" />
      )}
    </span>
  );
}

export default function PropagationSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });
  const [activeStep, setActiveStep] = useState(-1);
  const [signalY, setSignalY] = useState(0);
  const [signalVisible, setSignalVisible] = useState(false);

  const steps = [
    {
      num: '01',
      title: 'Discover',
      desc: 'Devices scan for nearby peers using Bluetooth LE and WiFi Direct. No manual setup.',
      hex: '0xA3F1…signal_scan',
    },
    {
      num: '02',
      title: 'Handshake',
      desc: 'Cryptographic key exchange happens in milliseconds. QR scan for verification. Zero trust assumed.',
      hex: '0x7B2E…key_exchange',
    },
    {
      num: '03',
      title: 'Encrypt',
      desc: 'Messages are sealed with the recipient\'s public key. Relay nodes carry ciphertext they can never read.',
      hex: '0xD4C8…nacl_seal',
    },
    {
      num: '04',
      title: 'Propagate',
      desc: 'The mesh finds the optimal path. Multi-hop routing with automatic failover. Your message always gets through.',
      hex: '0x91FA…mesh_route',
    },
  ];

  /* ── Sequential activation cascade ── */
  useEffect(() => {
    if (!isInView) return;
    const baseDelay = 1600;
    const stepDelay = 1200;
    const timers: NodeJS.Timeout[] = [];

    // Show signal pulse
    timers.push(setTimeout(() => setSignalVisible(true), baseDelay - 200));

    steps.forEach((_, i) => {
      timers.push(setTimeout(() => setActiveStep(i), baseDelay + i * stepDelay));
    });

    return () => timers.forEach(clearTimeout);
  }, [isInView]);

  /* ── Signal pulse traveling animation ── */
  const stepRefs = useRef<(HTMLDivElement | null)[]>([]);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (activeStep < 0 || !containerRef.current) return;
    const el = stepRefs.current[activeStep];
    if (!el) return;
    const containerTop = containerRef.current.getBoundingClientRect().top;
    const elTop = el.getBoundingClientRect().top;
    setSignalY(elTop - containerTop + 20);
  }, [activeStep]);

  const setStepRef = useCallback((i: number) => (el: HTMLDivElement | null) => {
    stepRefs.current[i] = el;
  }, []);

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32"
      id="propagation"
    >
      <div className="max-w-5xl mx-auto">
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8 }}
          className="mb-5 sm:mb-16"
        >
          <span className="mono-label text-[var(--color-copper)]">
            03 — Propagation
          </span>
        </motion.div>

        <motion.h2
          className="display-heading text-2xl sm:text-3xl md:text-5xl lg:text-6xl mb-4 sm:mb-8 max-w-3xl"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
        >
          <span className="text-[var(--color-ivory)]">Follow a signal</span>{' '}
          <span className="gradient-text-warm">through the mesh.</span>
        </motion.h2>

        {/* Steps with signal pulse */}
        <div className="mt-10 sm:mt-20 space-y-0 relative" ref={containerRef}>

          {/* Traveling signal pulse */}
          <AnimatePresence>
            {signalVisible && (
              <motion.div
                className="absolute left-[19px] sm:left-[29px] md:left-[39px] z-20 pointer-events-none"
                initial={{ top: 0, opacity: 0 }}
                animate={{ top: signalY, opacity: activeStep >= 0 ? 1 : 0 }}
                transition={{ type: 'spring', stiffness: 60, damping: 18, mass: 0.8 }}
              >
                {/* Glow core */}
                <div className="relative">
                  <div className="w-[9px] h-[9px] rounded-full bg-[var(--color-ember)] signal-glow" />
                  <div className="absolute inset-0 w-[9px] h-[9px] rounded-full bg-[var(--color-ember)] animate-ping opacity-40" />
                  {/* Trail */}
                  <motion.div
                    className="absolute left-[3.5px] bottom-[9px] w-[2px] origin-bottom"
                    animate={{ height: activeStep >= 0 ? 60 : 0, opacity: activeStep >= 0 ? 1 : 0 }}
                    transition={{ type: 'spring', stiffness: 80, damping: 20 }}
                    style={{ background: 'linear-gradient(to top, var(--color-ember), transparent)' }}
                  />
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Vertical progress line */}
          <div className="absolute left-[23px] sm:left-[33px] md:left-[43px] top-[20px] bottom-[20px] w-[1px] overflow-hidden">
            <motion.div
              className="w-full bg-gradient-to-b from-[var(--color-ember)] via-[var(--color-copper)] to-transparent"
              initial={{ height: '0%' }}
              animate={isInView ? { height: '100%' } : { height: '0%' }}
              transition={{ duration: 2.4, delay: 0.6, ease: [0.16, 1, 0.3, 1] }}
            />
          </div>

          {steps.map((step, i) => {
            const isActive = i <= activeStep;
            const isCurrent = i === activeStep;

            return (
              <motion.div
                key={i}
                ref={setStepRef(i)}
                initial={{ opacity: 0, x: -20 }}
                animate={isInView ? { opacity: 1, x: 0 } : {}}
                transition={{
                  duration: 0.8,
                  delay: 0.4 + i * 0.15,
                  ease: [0.16, 1, 0.3, 1],
                }}
                className="group relative grid grid-cols-[40px_1fr] sm:grid-cols-[60px_1fr] md:grid-cols-[80px_1fr_220px] gap-3 sm:gap-4 md:gap-8 py-4 sm:py-8 border-b border-[var(--color-slate)]/50 transition-all duration-700"
                style={{
                  borderBottomColor: isCurrent ? 'rgba(139, 92, 246, 0.25)' : undefined,
                }}
              >
                {/* Number with pulse ring */}
                <div className="relative font-[family-name:var(--font-mono)] text-sm pt-1">
                  <motion.span
                    animate={{
                      color: isActive ? '#8B5CF6' : '#262438',
                      textShadow: isCurrent ? '0 0 12px rgba(139,92,246,0.6)' : '0 0 0px transparent',
                    }}
                    transition={{ duration: 0.5 }}
                  >
                    {step.num}
                  </motion.span>
                  {/* Activation ring */}
                  <AnimatePresence>
                    {isCurrent && (
                      <motion.div
                        className="absolute -left-1 -top-0.5 w-7 h-7 rounded-full border border-[var(--color-ember)]"
                        initial={{ scale: 0.5, opacity: 0 }}
                        animate={{ scale: [1, 1.6, 1], opacity: [0.8, 0, 0.8] }}
                        exit={{ scale: 0.5, opacity: 0 }}
                        transition={{ duration: 1.5, repeat: Infinity, ease: 'easeInOut' }}
                      />
                    )}
                  </AnimatePresence>
                </div>

                {/* Content */}
                <div>
                  <motion.h3
                    className="font-[family-name:var(--font-display)] font-semibold text-lg sm:text-xl md:text-2xl mb-1 sm:mb-2 transition-colors duration-300"
                    animate={{
                      color: isActive ? '#F5F3FF' : '#878599',
                    }}
                    transition={{ duration: 0.6 }}
                  >
                    {step.title}
                  </motion.h3>
                  <motion.p
                    className="text-xs sm:text-sm md:text-base leading-relaxed max-w-lg"
                    animate={{
                      color: isActive ? '#D4D0E0' : '#878599',
                      opacity: isActive ? 1 : 0.5,
                    }}
                    transition={{ duration: 0.6 }}
                  >
                    {step.desc}
                  </motion.p>
                </div>

                {/* Hex indicator with typewriter */}
                <div className="hidden md:flex items-center">
                  <HexLabel text={step.hex} active={isActive} />
                </div>

                {/* Step activation glow bar */}
                <motion.div
                  className="absolute inset-0 pointer-events-none rounded-lg"
                  animate={{
                    background: isCurrent
                      ? 'linear-gradient(90deg, rgba(139,92,246,0.06) 0%, transparent 60%)'
                      : 'linear-gradient(90deg, transparent 0%, transparent 100%)',
                  }}
                  transition={{ duration: 0.8 }}
                />
              </motion.div>
            );
          })}

          {/* Final signal arrival indicator */}
          <AnimatePresence>
            {activeStep === steps.length - 1 && (
              <motion.div
                className="flex items-center gap-3 pt-6 sm:pt-10 pl-[40px] sm:pl-[60px] md:pl-[80px]"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.8, delay: 0.3, ease: [0.16, 1, 0.3, 1] }}
              >
                <div className="flex items-center gap-2">
                  <motion.div
                    className="w-2 h-2 rounded-full bg-green-400"
                    animate={{ boxShadow: ['0 0 4px #4ade80', '0 0 12px #4ade80', '0 0 4px #4ade80'] }}
                    transition={{ duration: 2, repeat: Infinity }}
                  />
                  <span className="font-[family-name:var(--font-mono)] text-xs text-green-400/80">
                    signal_delivered
                  </span>
                </div>
                <motion.span
                  className="font-[family-name:var(--font-mono)] text-xs text-[var(--color-slate)]"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.6 }}
                >
                  — 4 hops · 23ms · e2e encrypted
                </motion.span>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </section>
  );
}

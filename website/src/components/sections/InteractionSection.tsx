'use client';

import { useRef, useEffect, useState } from 'react';
import { motion, useInView, AnimatePresence } from 'framer-motion';
import { useMesh } from '@/lib/mesh-context';

export default function InteractionSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });
  const { triggerCascade, injectSignal, stateRef } = useMesh();
  const [clickCount, setClickCount] = useState(0);
  const [showRipple, setShowRipple] = useState(false);

  const handleTrigger = () => {
    triggerCascade();
    setClickCount(prev => prev + 1);
    setShowRipple(true);
    setTimeout(() => setShowRipple(false), 1200);
  };

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32"
      id="interaction"
    >
      <div className="max-w-4xl mx-auto text-center">
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8 }}
          className="mb-5 sm:mb-16"
        >
          <span className="mono-label text-[var(--color-gold)]">
            04 — Interaction
          </span>
        </motion.div>

        <motion.h2
          className="display-heading text-2xl sm:text-3xl md:text-5xl lg:text-6xl mb-4 sm:mb-6"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
        >
          <span className="text-[var(--color-ivory)]">You are</span>{' '}
          <span className="gradient-text-ember">the network.</span>
        </motion.h2>

        <motion.p
          className="text-sm sm:text-lg text-[var(--color-ash)] max-w-xl mx-auto mb-8 sm:mb-16 leading-relaxed px-2 sm:px-0"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8, delay: 0.4 }}
        >
          Every device running PeerChat strengthens the mesh.
          Click below to inject a signal — watch it propagate through the network behind this page.
        </motion.p>

        {/* Trigger button */}
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={isInView ? { opacity: 1, scale: 1 } : {}}
          transition={{ duration: 0.8, delay: 0.6, ease: [0.16, 1, 0.3, 1] }}
          className="relative inline-block"
        >
          <button
            onClick={handleTrigger}
            className="relative w-24 h-24 sm:w-32 sm:h-32 md:w-40 md:h-40 rounded-full border border-[var(--color-ember)]/40 bg-[var(--color-charcoal)] hover:bg-[var(--color-graphite)] transition-all duration-500 group cursor-pointer"
          >
            {/* Inner glow */}
            <div className="absolute inset-3 rounded-full bg-gradient-to-br from-[var(--color-ember)]/10 to-transparent group-hover:from-[var(--color-ember)]/20 transition-all duration-500" />

            {/* Center dot */}
            <div className="absolute inset-0 flex items-center justify-center">
              <div
                className="w-3 h-3 rounded-full transition-all duration-300"
                style={{
                  background: 'var(--color-ember)',
                  boxShadow: '0 0 20px rgba(139, 92, 246, 0.5)',
                  transform: showRipple ? 'scale(1.5)' : 'scale(1)',
                }}
              />
            </div>

            {/* Label */}
            <span className="absolute -bottom-10 left-1/2 -translate-x-1/2 mono-label text-[var(--color-ash)] group-hover:text-[var(--color-ember)] transition-colors whitespace-nowrap">
              Inject Signal
            </span>

            {/* Ripple effect */}
            <AnimatePresence>
              {showRipple && (
                <>
                  {[0, 1, 2].map(i => (
                    <motion.div
                      key={`ripple-${clickCount}-${i}`}
                      className="absolute inset-0 rounded-full border border-[var(--color-ember)]"
                      initial={{ scale: 1, opacity: 0.5 }}
                      animate={{ scale: 2.5, opacity: 0 }}
                      exit={{ opacity: 0 }}
                      transition={{
                        duration: 1.2,
                        delay: i * 0.15,
                        ease: [0.16, 1, 0.3, 1],
                      }}
                    />
                  ))}
                </>
              )}
            </AnimatePresence>
          </button>
        </motion.div>

        {/* Signal count */}
        <motion.div
          className="mt-12 sm:mt-20 flex items-center justify-center gap-6 sm:gap-12"
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8, delay: 0.8 }}
        >
          <div className="text-center">
            <div className="font-[family-name:var(--font-mono)] text-2xl text-[var(--color-ember)]">
              {clickCount}
            </div>
            <div className="mono-label mt-1">Signals sent</div>
          </div>
          <div className="w-[1px] h-8 bg-[var(--color-slate)]" />
          <div className="text-center">
            <div className="font-[family-name:var(--font-mono)] text-2xl text-[var(--color-copper)]">
              {Math.min(stateRef.current.nodes.length, Math.floor(clickCount * 3.5 + stateRef.current.nodes.length * 0.3))}
            </div>
            <div className="mono-label mt-1">Nodes active</div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}

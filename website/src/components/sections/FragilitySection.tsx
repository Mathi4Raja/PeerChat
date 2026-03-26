'use client';

import { useRef } from 'react';
import { motion, useInView } from 'framer-motion';

export default function FragilitySection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });

  const stats = [
    { value: '4.2B', label: 'people affected by disasters this decade' },
    { value: '72h', label: 'critical window where communication = survival' },
    { value: '0', label: 'cell towers needed by PeerChat' },
  ];

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32"
      id="fragility"
    >
      <div className="max-w-5xl mx-auto">
        {/* Label */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8 }}
          className="mb-5 sm:mb-16"
        >
          <span className="mono-label text-[#F43F5E]">
            01 — Fragility
          </span>
        </motion.div>

        {/* Statement */}
        <motion.h2
          className="display-heading text-2xl sm:text-3xl md:text-5xl lg:text-6xl mb-8 sm:mb-20 max-w-3xl"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
        >
          <span className="text-[var(--color-ivory)]">
            When infrastructure fails,
          </span>{' '}
          <span className="text-[var(--color-ash)]">
            centralized systems fail with it.
          </span>{' '}
          <span className="text-[#F43F5E]">
            Every connection severed. Every message lost.
          </span>
        </motion.h2>

        {/* Stats row */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 sm:gap-8">
          {stats.map((stat, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 20 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{
                duration: 0.8,
                delay: 0.5 + i * 0.2,
                ease: [0.16, 1, 0.3, 1],
              }}
              className="border-l border-[var(--color-slate)] pl-4 sm:pl-6 py-2 sm:py-4"
            >
              <div className="display-heading text-3xl sm:text-4xl md:text-5xl gradient-text-ember mb-1 sm:mb-2">
                {stat.value}
              </div>
              <p className="text-sm text-[var(--color-ash)] leading-relaxed">
                {stat.label}
              </p>
            </motion.div>
          ))}
        </div>

        {/* Visual line break */}
        <motion.div
          className="mt-10 sm:mt-20 h-[1px] bg-gradient-to-r from-transparent via-[var(--color-slate)] to-transparent"
          initial={{ scaleX: 0 }}
          animate={isInView ? { scaleX: 1 } : {}}
          transition={{ duration: 1.5, delay: 1, ease: [0.16, 1, 0.3, 1] }}
        />
      </div>
    </section>
  );
}

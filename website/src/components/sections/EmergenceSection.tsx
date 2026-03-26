'use client';

import { useRef, useEffect } from 'react';
import { motion, useInView } from 'framer-motion';
import { useMesh } from '@/lib/mesh-context';

export default function EmergenceSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });
  const { triggerCascade } = useMesh();
  const hasTriggered = useRef(false);

  useEffect(() => {
    if (isInView && !hasTriggered.current) {
      hasTriggered.current = true;
      // Trigger a cascade in the background mesh
      setTimeout(() => triggerCascade(), 800);
    }
  }, [isInView, triggerCascade]);

  const features = [
    {
      title: 'Zero Infrastructure',
      desc: 'Bluetooth and WiFi Direct create connections where none existed. Your phone becomes a relay tower.',
      accent: 'var(--color-ember)',
    },
    {
      title: 'Multi-Hop Routing',
      desc: 'Messages traverse multiple devices to reach their destination. If one path fails, another is found.',
      accent: 'var(--color-copper)',
    },
    {
      title: 'Self-Healing Mesh',
      desc: 'The network constantly adapts. Nodes join, leave, move — the mesh reconfigures instantly.',
      accent: 'var(--color-gold)',
    },
  ];

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32"
      id="emergence"
    >
      <div className="max-w-5xl mx-auto">
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8 }}
          className="mb-5 sm:mb-16"
        >
          <span className="mono-label text-[var(--color-ember)]">
            02 — Emergence
          </span>
        </motion.div>

        <motion.h2
          className="display-heading text-2xl sm:text-3xl md:text-5xl lg:text-6xl mb-4 sm:mb-8 max-w-3xl"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
        >
          <span className="text-[var(--color-ivory)]">A network forms</span>{' '}
          <span className="gradient-text-ember">from nothing.</span>
        </motion.h2>

        <motion.p
          className="text-sm sm:text-lg text-[var(--color-ash)] max-w-xl mb-8 sm:mb-20 leading-relaxed"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8, delay: 0.4 }}
        >
          PeerChat doesn't need the internet. Each device that runs it becomes
          a node in a living, decentralized mesh. The more people join, the
          stronger the network becomes.
        </motion.p>

        {/* Feature cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 sm:gap-6">
          {features.map((feature, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 24 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{
                duration: 0.8,
                delay: 0.6 + i * 0.15,
                ease: [0.16, 1, 0.3, 1],
              }}
              className="group relative p-4 sm:p-6 rounded-2xl border border-[var(--color-slate)] bg-[rgba(17,17,17,0.5)] backdrop-blur-sm hover:border-[var(--color-ember)]/30 transition-all duration-500 cursor-default"
            >
              {/* Accent bar */}
              <div
                className="w-8 h-[2px] mb-4 sm:mb-6 transition-all duration-500 group-hover:w-12"
                style={{ background: feature.accent }}
              />
              <h3 className="font-[family-name:var(--font-display)] font-semibold text-lg text-[var(--color-ivory)] mb-3">
                {feature.title}
              </h3>
              <p className="text-sm text-[var(--color-ash)] leading-relaxed">
                {feature.desc}
              </p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

'use client';

import { useRef, useEffect, useState, useMemo } from 'react';
import { motion, useInView } from 'framer-motion';

/* ── Floating mesh nodes for mobile top area ── */
const MESH_PARTICLES = [
  { x: 15, y: 18, size: 4, delay: 0 },
  { x: 45, y: 12, size: 3, delay: 0.3 },
  { x: 75, y: 22, size: 5, delay: 0.6 },
  { x: 30, y: 30, size: 3, delay: 0.9 },
  { x: 60, y: 8, size: 4, delay: 0.2 },
  { x: 85, y: 32, size: 3, delay: 0.5 },
  { x: 20, y: 6, size: 3, delay: 0.8 },
  { x: 50, y: 28, size: 4, delay: 0.4 },
  { x: 10, y: 35, size: 3, delay: 0.7 },
  { x: 90, y: 15, size: 3, delay: 1.0 },
  { x: 38, y: 38, size: 3, delay: 0.1 },
  { x: 70, y: 36, size: 4, delay: 0.55 },
];

/* ── Connections between particles (index pairs) ── */
const MESH_LINES: [number, number][] = [
  [0, 3], [1, 4], [1, 7], [2, 5], [3, 7],
  [4, 1], [5, 11], [6, 0], [7, 11], [8, 3],
  [9, 2], [10, 7], [10, 8], [0, 1], [2, 11],
];

export default function HeroSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true });
  const [stage, setStage] = useState(0);

  useEffect(() => {
    if (!isInView) return;
    const timers = [
      setTimeout(() => setStage(1), 300),
      setTimeout(() => setStage(2), 800),
      setTimeout(() => setStage(3), 1400),
      setTimeout(() => setStage(4), 2000),
      setTimeout(() => setStage(5), 2600),
    ];
    return () => timers.forEach(clearTimeout);
  }, [isInView]);

  /* ── Randomised drift offsets (stable per mount) ── */
  const drifts = useMemo(
    () =>
      MESH_PARTICLES.map((_, i) => ({
        dx: ((i * 7 + 3) % 11) - 5,
        dy: ((i * 5 + 2) % 9) - 4,
      })),
    []
  );

  return (
    <section
      ref={ref}
      className="section-full section-hero items-center justify-center px-4 sm:px-6 relative"
      id="hero"
    >
      {/* ── Mobile mesh animation (fills empty top area) ── */}
      <div className="absolute inset-x-0 top-0 h-[45vh] sm:hidden pointer-events-none overflow-hidden">
        <svg
          className="w-full h-full"
          viewBox="0 0 100 42"
          preserveAspectRatio="xMidYMid slice"
          fill="none"
        >
          {/* Connection lines */}
          {MESH_LINES.map(([a, b], i) => {
            const from = MESH_PARTICLES[a];
            const to = MESH_PARTICLES[b];
            return (
              <motion.line
                key={`line-${i}`}
                x1={from.x}
                y1={from.y}
                x2={to.x}
                y2={to.y}
                stroke="#8B5CF6"
                strokeWidth={0.15}
                initial={{ opacity: 0, pathLength: 0 }}
                animate={
                  stage >= 2
                    ? { opacity: [0, 0.15, 0.08], pathLength: 1 }
                    : {}
                }
                transition={{
                  opacity: { duration: 3, delay: 0.8 + i * 0.12, repeat: Infinity, repeatType: 'reverse' },
                  pathLength: { duration: 1.5, delay: 0.8 + i * 0.12 },
                }}
              />
            );
          })}

          {/* Particle nodes */}
          {MESH_PARTICLES.map((p, i) => (
            <motion.circle
              key={`dot-${i}`}
              cx={p.x}
              cy={p.y}
              r={p.size * 0.25}
              fill="#8B5CF6"
              initial={{ opacity: 0, scale: 0 }}
              animate={
                stage >= 1
                  ? {
                      opacity: [0, 0.6, 0.25, 0.5],
                      scale: 1,
                      cx: [p.x, p.x + drifts[i].dx, p.x - drifts[i].dx * 0.5, p.x],
                      cy: [p.y, p.y + drifts[i].dy, p.y - drifts[i].dy * 0.5, p.y],
                    }
                  : {}
              }
              transition={{
                opacity: { duration: 4 + i * 0.3, delay: p.delay, repeat: Infinity, repeatType: 'reverse' },
                scale: { duration: 0.6, delay: p.delay },
                cx: { duration: 8 + i * 0.5, delay: p.delay, repeat: Infinity, repeatType: 'reverse', ease: 'easeInOut' },
                cy: { duration: 7 + i * 0.4, delay: p.delay, repeat: Infinity, repeatType: 'reverse', ease: 'easeInOut' },
              }}
            />
          ))}

          {/* Traveling signal pulses along some lines */}
          {stage >= 3 &&
            [0, 3, 6, 9, 13].map((lineIdx) => {
              const [a, b] = MESH_LINES[lineIdx];
              const from = MESH_PARTICLES[a];
              const to = MESH_PARTICLES[b];
              return (
                <motion.circle
                  key={`pulse-${lineIdx}`}
                  r={0.4}
                  fill="white"
                  initial={{ opacity: 0 }}
                  animate={{
                    cx: [from.x, to.x],
                    cy: [from.y, to.y],
                    opacity: [0, 0.8, 0.8, 0],
                  }}
                  transition={{
                    duration: 2.5,
                    delay: lineIdx * 0.6,
                    repeat: Infinity,
                    repeatDelay: 3 + lineIdx * 0.4,
                    ease: 'easeInOut',
                  }}
                />
              );
            })}
        </svg>

        {/* Fade-out gradient at bottom */}
        <div
          className="absolute inset-x-0 bottom-0 h-20"
          style={{
            background: 'linear-gradient(to top, var(--color-ink), transparent)',
          }}
        />
      </div>

      <div className="max-w-4xl mx-auto text-center relative z-10">
        {/* Status indicator */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={stage >= 1 ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
          className="mb-4 sm:mb-8"
        >
          <span className="mono-label inline-flex items-center gap-2">
            <span
              className="w-1.5 h-1.5 rounded-full"
              style={{
                background: stage >= 2 ? '#8B5CF6' : '#262438',
                boxShadow: stage >= 2 ? '0 0 8px rgba(139,92,246,0.5)' : 'none',
                transition: 'all 1s ease',
              }}
            />
            {stage >= 2 ? 'Network Awakening' : 'Initializing'}
          </span>
        </motion.div>

        {/* Main headline */}
        <h1 className="display-heading text-3xl sm:text-5xl md:text-7xl lg:text-8xl mb-4 sm:mb-6">
          <motion.span
            className="block"
            initial={{ opacity: 0, y: 40 }}
            animate={stage >= 2 ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: 1.2, ease: [0.16, 1, 0.3, 1] }}
          >
            <span className="text-[var(--color-ivory)]">Messages that</span>
          </motion.span>
          <motion.span
            className="block gradient-text-ember"
            initial={{ opacity: 0, y: 40 }}
            animate={stage >= 3 ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: 1.2, ease: [0.16, 1, 0.3, 1] }}
          >
            find their way.
          </motion.span>
        </h1>

        {/* Subline */}
        <motion.p
          className="text-base sm:text-lg md:text-xl text-[var(--color-ash)] max-w-xl mx-auto mb-8 sm:mb-12 leading-relaxed px-2 sm:px-0"
          initial={{ opacity: 0, y: 20 }}
          animate={stage >= 4 ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, ease: [0.16, 1, 0.3, 1] }}
        >
          Peer-to-peer encrypted messaging and file transfers. No servers. No infrastructure.
          Connect via BLE, WiFi Direct, or WiFi Hotspot — your device becomes the network.
        </motion.p>

        {/* CTA */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={stage >= 5 ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
          className="flex justify-center"
        >
          <button className="group relative px-6 py-3 sm:px-8 sm:py-4 rounded-full bg-[var(--color-ember)] text-white font-medium text-sm sm:text-base overflow-hidden transition-all duration-300 hover:shadow-[0_0_40px_rgba(139,92,246,0.3)]">
            <span className="relative z-10">Get the Mobile app</span>
            <div className="absolute inset-0 bg-gradient-to-r from-[var(--color-ember)] to-[var(--color-copper)] opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
          </button>
        </motion.div>
      </div>

      {/* Scroll indicator */}
      <motion.div
        className="absolute bottom-8 left-1/2 -translate-x-1/2"
        initial={{ opacity: 0 }}
        animate={stage >= 5 ? { opacity: 1 } : {}}
        transition={{ duration: 1, delay: 0.5 }}
      >
        <div className="w-[1px] h-12 bg-gradient-to-b from-[var(--color-ember)] to-transparent mx-auto animate-pulse" />
      </motion.div>
    </section>
  );
}

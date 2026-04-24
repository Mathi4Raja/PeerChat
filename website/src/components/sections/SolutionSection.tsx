'use client';

import { motion, useInView, useScroll, useTransform, AnimatePresence } from 'framer-motion';
import { useRef, useState, useEffect } from 'react';

const NODE_COLORS = [
  '#8B5CF6', '#6366F1', '#A78BFA', '#7C3AED',
  '#8B5CF6', '#6366F1', '#A78BFA', '#7C3AED',
];

export default function SolutionSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: '-100px' });
  const [activeNodes, setActiveNodes] = useState<number[]>([]);
  const [hoveredNode, setHoveredNode] = useState<number | null>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'end start'] });
  const coolTransition = useTransform(scrollYProgress, [0, 0.3], [0, 1]);
  const [responsiveR, setResponsiveR] = useState(140);

  useEffect(() => {
    const update = () => setResponsiveR(window.innerWidth < 640 ? 100 : 140);
    update();
    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, []);

  useEffect(() => {
    if (isInView) {
      const interval = setInterval(() => {
        setActiveNodes((prev) => (prev.length < 8 ? [...prev, prev.length] : prev));
      }, 180);
      return () => clearInterval(interval);
    }
  }, [isInView]);

  const nodePositions = [
    { x: 0, y: -1 },
    { x: 0.7, y: -0.7 },
    { x: 1, y: 0 },
    { x: 0.7, y: 0.7 },
    { x: 0, y: 1 },
    { x: -0.7, y: 0.7 },
    { x: -1, y: 0 },
    { x: -0.7, y: -0.7 },
  ];
  const svgHalf = responsiveR + 30;

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32 overflow-hidden"
      id="solution"
    >
      {/* Background radial glow */}
      <motion.div
        className="absolute inset-0 pointer-events-none"
        style={{
          opacity: coolTransition,
          background:
            'radial-gradient(ellipse at 40% 40%, rgba(99,102,241,0.08) 0%, transparent 50%), radial-gradient(ellipse at 60% 60%, rgba(139,92,246,0.06) 0%, transparent 50%)',
          filter: 'blur(60px)',
        }}
      />

      <div className="relative z-10 max-w-[1280px] mx-auto w-full">
        {/* Header */}
        <motion.div
          className="text-center mb-10 sm:mb-20"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8, ease: [0.22, 1, 0.36, 1] }}
        >
          <span className="mono-label text-[var(--color-ember)] mb-4 block">
            The Solution
          </span>
          <h2 className="display-heading text-2xl sm:text-3xl md:text-5xl lg:text-6xl mb-4">
            <span className="text-[var(--color-ivory)]">PeerChat doesn&apos;t rely on servers.</span>
            <br />
            <span className="gradient-text-ember">It becomes the network.</span>
          </h2>
        </motion.div>

        {/* Network visualization */}
        <div className="relative flex items-center justify-center mb-10 sm:mb-20" style={{ height: '320px' }}>
          {/* SVG lines + traveling particles */}
          <svg
            className="absolute"
            style={{ width: svgHalf * 2, height: svgHalf * 2 }}
            viewBox={`${-svgHalf} ${-svgHalf} ${svgHalf * 2} ${svgHalf * 2}`}
          >
            {/* Connection lines between nodes */}
            {activeNodes.map((i) =>
              activeNodes
                .filter((j) => j > i && (Math.abs(j - i) <= 2 || Math.abs(j - i) >= 6))
                .map((j) => (
                  <motion.line
                    key={`${i}-${j}`}
                    x1={nodePositions[i].x * responsiveR}
                    y1={nodePositions[i].y * responsiveR}
                    x2={nodePositions[j].x * responsiveR}
                    y2={nodePositions[j].y * responsiveR}
                    initial={{ opacity: 0, pathLength: 0, strokeWidth: 0.8 }}
                    animate={{
                      opacity: 1,
                      pathLength: 1,
                      stroke:
                        hoveredNode === i || hoveredNode === j
                          ? NODE_COLORS[i]
                          : 'rgba(139,92,246,0.12)',
                      strokeWidth: hoveredNode === i || hoveredNode === j ? 2 : 0.8,
                    }}
                    transition={{
                      duration: 0.8,
                      stroke: { duration: 0.5, ease: 'easeOut' },
                      strokeWidth: { duration: 0.5, ease: 'easeOut' },
                    }}
                  />
                ))
            )}

            {/* Traveling dot particles */}
            {activeNodes.length === 8 && (
              <>
                <motion.circle
                  r="3"
                  fill="#8B5CF6"
                  filter="url(#glow-solution)"
                  animate={{
                    cx: [nodePositions[0].x * responsiveR, nodePositions[1].x * responsiveR, nodePositions[2].x * responsiveR, nodePositions[3].x * responsiveR],
                    cy: [nodePositions[0].y * responsiveR, nodePositions[1].y * responsiveR, nodePositions[2].y * responsiveR, nodePositions[3].y * responsiveR],
                    opacity: [0, 1, 1, 0],
                  }}
                  transition={{ duration: 3.5, repeat: Infinity, ease: 'linear' }}
                />
                <motion.circle
                  r="3"
                  fill="#6366F1"
                  filter="url(#glow-solution)"
                  animate={{
                    cx: [nodePositions[4].x * responsiveR, nodePositions[5].x * responsiveR, nodePositions[6].x * responsiveR, nodePositions[7].x * responsiveR],
                    cy: [nodePositions[4].y * responsiveR, nodePositions[5].y * responsiveR, nodePositions[6].y * responsiveR, nodePositions[7].y * responsiveR],
                    opacity: [0, 1, 1, 0],
                  }}
                  transition={{ duration: 3.5, repeat: Infinity, ease: 'linear', delay: 1.75 }}
                />
                <motion.circle
                  r="2.5"
                  fill="#A78BFA"
                  filter="url(#glow-solution)"
                  animate={{
                    cx: [nodePositions[2].x * responsiveR, nodePositions[3].x * responsiveR, nodePositions[4].x * responsiveR, nodePositions[5].x * responsiveR],
                    cy: [nodePositions[2].y * responsiveR, nodePositions[3].y * responsiveR, nodePositions[4].y * responsiveR, nodePositions[5].y * responsiveR],
                    opacity: [0, 1, 1, 0],
                  }}
                  transition={{ duration: 4, repeat: Infinity, ease: 'linear', delay: 0.8 }}
                />
                <defs>
                  <filter id="glow-solution">
                    <feGaussianBlur stdDeviation="3" result="coloredBlur" />
                    <feMerge>
                      <feMergeNode in="coloredBlur" />
                      <feMergeNode in="SourceGraphic" />
                    </feMerge>
                  </filter>
                </defs>
              </>
            )}
          </svg>

          {/* Interactive node circles */}
          {nodePositions.map((pos, i) => {
            const isActive = activeNodes.includes(i);
            const isHovered = hoveredNode === i;
            const color = NODE_COLORS[i];
            return (
              <motion.div
                key={i}
                className="absolute cursor-pointer"
                style={{
                  left: `calc(50% + ${pos.x * responsiveR}px - 22px)`,
                  top: `calc(50% + ${pos.y * responsiveR}px - 22px)`,
                }}
                initial={{ opacity: 0, scale: 0 }}
                animate={isActive ? { opacity: 1, scale: isHovered ? 1.3 : 1 } : { opacity: 0, scale: 0 }}
                transition={{
                  duration: 0.5,
                  ease: [0.22, 1, 0.36, 1],
                  scale: { type: 'spring', stiffness: 300, damping: 20 },
                }}
                onMouseEnter={() => setHoveredNode(i)}
                onMouseLeave={() => setHoveredNode(null)}
              >
                {/* Ripple ring on hover */}
                {isHovered && (
                  <motion.div
                    className="absolute inset-0 rounded-full"
                    style={{ border: `1.5px solid ${color}` }}
                    initial={{ scale: 1, opacity: 0.6 }}
                    animate={{ scale: 2.5, opacity: 0 }}
                    transition={{ duration: 1.2, repeat: Infinity }}
                  />
                )}
                {/* Node circle */}
                <div
                  className="w-9 h-9 sm:w-11 sm:h-11 rounded-full flex items-center justify-center transition-all duration-300"
                  style={{
                    background: `${color}15`,
                    border: `1.5px solid ${color}${isHovered ? '60' : '30'}`,
                    boxShadow: isHovered ? `0 0 25px ${color}40` : 'none',
                  }}
                >
                  <div
                    className="w-2.5 h-2.5 sm:w-3 sm:h-3 rounded-full transition-all duration-300"
                    style={{
                      background: color,
                      boxShadow: isHovered ? `0 0 10px ${color}` : 'none',
                    }}
                  />
                </div>
              </motion.div>
            );
          })}

          {/* Center hub */}
          <motion.div
            className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-14 h-14 sm:w-16 sm:h-16 rounded-full flex items-center justify-center"
            style={{
              background: 'linear-gradient(135deg, rgba(139,92,246,0.1), rgba(99,102,241,0.08))',
              border: '1.5px solid rgba(139,92,246,0.25)',
            }}
            initial={{ opacity: 0, scale: 0 }}
            animate={
              isInView
                ? {
                    opacity: 1,
                    scale: 1,
                    boxShadow: [
                      '0 0 0px rgba(139,92,246,0)',
                      '0 0 40px rgba(139,92,246,0.3)',
                      '0 0 0px rgba(139,92,246,0)',
                    ],
                  }
                : {}
            }
            transition={{
              opacity: { duration: 0.6, delay: 0.3 },
              scale: { duration: 0.8, delay: 0.3, type: 'spring' },
              boxShadow: { duration: 3, repeat: Infinity, delay: 1 },
            }}
          >
            <div
              className="w-4 h-4 sm:w-5 sm:h-5 rounded-full"
              style={{ background: 'linear-gradient(135deg, #8B5CF6, #6366F1)' }}
            />
          </motion.div>
        </div>

        {/* Feature cards */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 sm:gap-10 max-w-3xl mx-auto">
          {[
            {
              title: 'Decentralized',
              description: 'No single point of failure. The network adapts and continues.',
              color: '#8B5CF6',
            },
            {
              title: 'Resilient',
              description: 'Works via BLE, WiFi Direct, and WiFi Hotspot. Transfer files or messages — the mesh adapts when reconnected.',
              color: '#6366F1',
            },
            {
              title: 'Unstoppable',
              description: 'Impossible to censor or shut down. Pure peer-to-peer architecture.',
              color: '#A78BFA',
            },
          ].map((item, i) => (
            <motion.div
              key={i}
              className="text-center group cursor-default"
              initial={{ opacity: 0, y: 25 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.7, delay: 0.5 + i * 0.12, ease: [0.22, 1, 0.36, 1] }}
            >
              <motion.div
                className="w-2.5 h-2.5 rounded-full mx-auto mb-4 sm:mb-5"
                style={{ background: item.color }}
                whileHover={{ scale: 2.5, boxShadow: `0 0 15px ${item.color}` }}
                transition={{ type: 'spring', stiffness: 400 }}
              />
              <h3 className="font-[family-name:var(--font-display)] font-semibold text-base sm:text-lg text-[var(--color-ivory)] mb-2">
                {item.title}
              </h3>
              <p className="text-xs sm:text-sm text-[var(--color-ash)] leading-relaxed">
                {item.description}
              </p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

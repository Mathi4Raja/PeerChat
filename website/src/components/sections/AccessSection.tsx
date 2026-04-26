'use client'; // Updated for Patron card transformation

import { useRef, useState } from 'react';
import { motion, useInView, AnimatePresence } from 'framer-motion';

interface Plan {
  id: string;
  name: string;
  tagline: string;
  price: string;
  period: string;
  features: string[];
  accent: string;
  nodeLabel: string;
}

const plans: Plan[] = [
  {
    id: 'independent',
    name: 'Independent',
    tagline: 'A sovereign node',
    price: 'Free',
    period: 'forever',
    features: [
      'Peer-to-peer messaging',
      'WiFi Direct & Hotspot file sharing',
      'End-to-end encryption',
      'Multi-hop mesh routing',
      'Emergency broadcast',
      'QR code pairing',
      'Open source',
    ],
    accent: 'var(--color-ember)',
    nodeLabel: 'INDEPENDENT',
  },
  {
    id: 'patron',
    name: 'Patron',
    tagline: 'Support the revolution',
    price: 'Donate',
    period: 'one-time / monthly',
    features: [
      'Support Peer-to-peer R&D',
      'Fund global relay infrastructure',
      'Help keep PeerChat open source',
      'Direct impact on net neutrality',
      'No data harvesting, ever',
      'Accelerate decentralized network growth',
      'Empower community-led development',
    ],
    accent: 'var(--color-gold)',
    nodeLabel: 'SUPPORTER',
  },
];

export default function AccessSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.2 });
  const [selectedPlan, setSelectedPlan] = useState<string | null>(null);

  return (
    <section
      ref={ref}
      className="section-full items-center justify-center px-4 sm:px-6 py-10 sm:py-32"
      id="access"
    >
      <div className="max-w-5xl mx-auto">
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8 }}
          className="mb-5 sm:mb-16 text-center"
        >
          <span className="mono-label text-[var(--color-gold)]">
            06 — Access
          </span>
        </motion.div>

        <motion.h2
          className="display-heading text-2xl sm:text-3xl md:text-5xl lg:text-6xl mb-4 sm:mb-6 text-center"
          initial={{ opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 1, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
        >
          <span className="text-[var(--color-ivory)]">Choose your</span>{' '}
          <span className="gradient-text-ember">role in the mesh.</span>
        </motion.h2>

        <motion.p
          className="text-sm sm:text-lg text-[var(--color-ash)] max-w-xl mx-auto mb-8 sm:mb-20 text-center leading-relaxed px-2 sm:px-0"
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8, delay: 0.4 }}
        >
          Every node matters. Choose the one that fits.
        </motion.p>

        {/* Plan nodes */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-3xl mx-auto">
          {plans.map((plan, i) => {
            const isSelected = selectedPlan === plan.id;

            return (
              <motion.div
                key={plan.id}
                initial={{ opacity: 0, y: 24 }}
                animate={isInView ? { opacity: 1, y: 0 } : {}}
                transition={{
                  duration: 0.8,
                  delay: 0.5 + i * 0.15,
                  ease: [0.16, 1, 0.3, 1],
                }}
                className={`plan-node relative rounded-2xl border ${
                  isSelected
                    ? 'plan-node-active'
                    : 'border-[var(--color-slate)]'
                } bg-[var(--color-charcoal)] p-5 sm:p-8 overflow-hidden`}
                onClick={() => setSelectedPlan(isSelected ? null : plan.id)}
              >
                {/* Top accent */}
                <div
                  className="absolute top-0 left-0 right-0 h-[1px]"
                  style={{
                    background: `linear-gradient(90deg, transparent, ${plan.accent}, transparent)`,
                    opacity: isSelected ? 1 : 0.3,
                    transition: 'opacity 0.5s ease',
                  }}
                />

                {/* Node indicator */}
                <div className="flex items-center gap-3 mb-4 sm:mb-6">
                  <div
                    className="w-3 h-3 rounded-full transition-all duration-500"
                    style={{
                      background: plan.accent,
                      boxShadow: isSelected
                        ? `0 0 16px ${plan.accent}`
                        : `0 0 4px ${plan.accent}`,
                    }}
                  />
                  <span className="mono-label" style={{ color: plan.accent }}>
                    {plan.nodeLabel}
                  </span>
                </div>

                {/* Name & tagline */}
                <h3 className="font-[family-name:var(--font-display)] font-bold text-2xl text-[var(--color-ivory)] mb-1">
                  {plan.name}
                </h3>
                <p className="text-sm text-[var(--color-ash)] mb-4 sm:mb-6">
                  {plan.tagline}
                </p>

                {/* Price */}
                <div className="mb-6 sm:mb-8">
                  <span className="display-heading text-3xl sm:text-4xl" style={{ color: plan.accent }}>
                    {plan.price}
                  </span>
                  <span className="text-[var(--color-ash)] text-sm ml-1">
                    {plan.period}
                  </span>
                </div>

                {/* Features — expand on select */}
                <AnimatePresence>
                  {(isSelected || true) && (
                    <motion.div
                      initial={false}
                      animate={{ height: 'auto', opacity: 1 }}
                      className="space-y-3"
                    >
                      {plan.features.map((feature, fi) => (
                        <motion.div
                          key={fi}
                          initial={{ opacity: 0, x: -8 }}
                          animate={isInView ? { opacity: 1, x: 0 } : {}}
                          transition={{
                            delay: 0.7 + i * 0.15 + fi * 0.05,
                            duration: 0.4,
                          }}
                          className="flex items-center gap-3 text-sm"
                        >
                          <div
                            className="w-1 h-1 rounded-full flex-shrink-0"
                            style={{ background: plan.accent }}
                          />
                          <span className="text-[var(--color-mist)]">
                            {feature}
                          </span>
                        </motion.div>
                      ))}
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* CTA */}
                <motion.a
                  href={plan.price === 'Free' ? "/api/download/PeerChat.apk" : "/donateus"}
                  download={plan.price === 'Free' ? true : undefined}
                  target="_self"
                  onClick={(e) => {
                    e.stopPropagation();
                  }}
                  className="mt-8 w-full block text-center py-3 rounded-full text-sm font-medium transition-all duration-300"
                  style={{
                    background: isSelected ? plan.accent : 'transparent',
                    color: isSelected ? '#0a0a0a' : plan.accent,
                    border: `1px solid ${plan.accent}`,
                    opacity: isSelected ? 1 : 0.7,
                  }}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                >
                  {plan.price === 'Free' ? 'Download Now' : 'Donate Us'}
                </motion.a>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

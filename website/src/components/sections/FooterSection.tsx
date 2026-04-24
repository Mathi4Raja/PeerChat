'use client';

import { motion, useInView } from 'framer-motion';
import { useRef, useEffect, useState } from 'react';

export default function FooterSection() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.3 });
  const [stars, setStars] = useState<number | null>(null);

  useEffect(() => {
    fetch('https://api.github.com/repos/Mathi4Raja/PeerChat')
      .then(res => res.json())
      .then(data => {
        if (typeof data.stargazers_count === 'number') {
          setStars(data.stargazers_count);
        }
      })
      .catch(err => console.error('Error fetching stars:', err));
  }, []);

  return (
    <footer ref={ref} className="px-4 sm:px-6 py-8 sm:py-20 border-t border-[var(--color-slate)]/30">
      <div className="max-w-5xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.8 }}
          className="grid grid-cols-2 md:grid-cols-4 gap-6 sm:gap-8 mb-8 sm:mb-16"
        >
          {/* Brand */}
          <div className="col-span-2 md:col-span-1">
            <div className="flex items-center gap-2 mb-4">
              <div className="w-2 h-2 rounded-full bg-[var(--color-ember)]" style={{ boxShadow: '0 0 8px rgba(139,92,246,0.5)' }} />
              <span className="font-[family-name:var(--font-display)] font-bold text-[var(--color-ivory)]">
                PeerChat
              </span>
            </div>
            <p className="text-sm text-[var(--color-ash)] leading-relaxed">
              Peer-to-peer encrypted mesh messaging.
              No servers. No compromises.
            </p>
          </div>

          {/* Network Links */}
          <nav aria-label="Footer navigation">
            <h4 className="mono-label mb-4 text-[var(--color-copper)]">Network</h4>
            <ul className="space-y-2 text-sm text-[var(--color-ash)]">
              {[
                { label: 'GitHub', href: 'https://github.com/Mathi4Raja/P2P-app' },
                { label: 'Documentation', href: 'https://github.com/Mathi4Raja/P2P-app#readme' },
                { label: 'Protocol Spec', href: 'https://github.com/Mathi4Raja/P2P-app/blob/main/README.md' },
                { label: 'Security Audit', href: '#' }
              ].map(link => (
                <li key={link.label}>
                  <a
                    href={link.href}
                    target={link.href.startsWith('http') ? "_blank" : undefined}
                    rel={link.href.startsWith('http') ? "noopener noreferrer" : undefined}
                    className="hover:text-[var(--color-ember)] transition-colors duration-300"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>

          {/* Legal Links */}
          <nav aria-label="Legal navigation">
            <h4 className="mono-label mb-4 text-[var(--color-ember)]">Legal</h4>
            <ul className="space-y-2 text-sm text-[var(--color-ash)]">
              {[
                { label: 'Changelog', href: '/changelog' },
                { label: 'Terms of Service', href: '/tos' },
                { label: 'Privacy Policy', href: '/policies' },
                { label: 'Donate', href: '/donateus' },
              ].map(link => (
                <li key={link.label}>
                  <a
                    href={link.href}
                    className="hover:text-[var(--color-ember)] transition-colors duration-300"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>

          {/* Metrics */}
          <div>
            <h4 className="mono-label mb-4 text-[var(--color-sage)]">GitHub Stars</h4>
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <div className="w-1.5 h-1.5 rounded-full bg-[var(--color-sage)]" />
                <span className="font-[family-name:var(--font-display)] font-bold text-xl text-[var(--color-ivory)]">
                  {stars !== null ? stars : '0'}
                </span>
              </div>
              <p className="text-sm text-[var(--color-ash)]">
                Stars on GitHub
              </p>
            </div>
          </div>
        </motion.div>

        {/* Bottom */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ duration: 0.8, delay: 0.3 }}
          className="pt-8 border-t border-[var(--color-slate)]/20 flex flex-col sm:flex-row items-center justify-between gap-3"
        >
          <p className="font-[family-name:var(--font-mono)] text-sm text-[var(--color-ash)]">
            © {new Date().getFullYear()} PeerChat.
          </p>
          <div className="flex gap-5">
            {[
              { label: 'Terms', href: '/tos' },
              { label: 'Privacy', href: '/policies' },
              { label: 'Changelog', href: '/changelog' },
            ].map(l => (
              <a
                key={l.label}
                href={l.href}
                className="font-[family-name:var(--font-mono)] text-xs text-[var(--color-ash)] hover:text-[var(--color-ember)] transition-colors"
              >
                {l.label}
              </a>
            ))}
          </div>
          <p className="font-[family-name:var(--font-mono)] text-xs text-[var(--color-slate)]">
            The network is the people.
          </p>
        </motion.div>
      </div>
    </footer>
  );
}

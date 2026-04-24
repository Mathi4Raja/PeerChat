import type { Metadata } from 'next';
import SubPageLayout from '@/components/SubPageLayout';

export const metadata: Metadata = {
  title: 'Support PeerChat — Donate',
  description:
    'Support PeerChat development via Ko-fi or UPI. Every contribution keeps the project open source and server-free.',
  alternates: { canonical: 'https://peerchat.mathi.live/donateus' },
};

const UPI_ID = 'mathi4raja@okaxis';
const UPI_QR_DATA = `upi://pay?pa=${UPI_ID}&pn=PeerChat&cu=INR`;

export default function DonatePage() {
  return (
    <SubPageLayout
      title="Support PeerChat"
      subtitle="Free, open source, no ads — forever. If PeerChat helps you, consider supporting the project."
      badge="Donate"
    >
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5 mb-5">
        {/* Ko-fi */}
        <div
          className="rounded-2xl border border-[var(--color-slate)] bg-[var(--color-charcoal)] p-7 flex flex-col gap-5"
          style={{ borderTop: '2px solid rgba(255,94,91,0.35)' }}
        >
          <div className="flex items-center gap-4">
            <div
              className="w-11 h-11 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ background: 'rgba(255,94,91,0.1)', border: '1px solid rgba(255,94,91,0.2)' }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FF5E5B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M18 8h1a4 4 0 0 1 0 8h-1" />
                <path d="M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z" />
                <line x1="6" y1="1" x2="6" y2="4" />
                <line x1="10" y1="1" x2="10" y2="4" />
                <line x1="14" y1="1" x2="14" y2="4" />
              </svg>
            </div>
            <div>
              <h2 className="font-[family-name:var(--font-display)] font-bold text-lg text-[var(--color-ivory)]">Ko-fi</h2>
              <p className="text-sm text-[var(--color-ash)]">Card · PayPal · International</p>
            </div>
          </div>
          <p className="text-sm text-[var(--color-ash)] leading-relaxed flex-1">
            One-time or monthly. Ko-fi accepts all major cards, PayPal, and Google Pay — no account needed.
          </p>
          <a
            href="https://ko-fi.com/mathi4raja"
            target="_blank"
            rel="noopener noreferrer"
            className="w-full py-3 rounded-xl text-center text-sm font-semibold transition-all duration-300 hover:opacity-80"
            style={{ background: 'rgba(255,94,91,0.12)', color: '#FF5E5B', border: '1px solid rgba(255,94,91,0.3)' }}
          >
            Support on Ko-fi →
          </a>
        </div>

        {/* UPI */}
        <div
          className="rounded-2xl border border-[var(--color-slate)] bg-[var(--color-charcoal)] p-7 flex flex-col gap-5"
          style={{ borderTop: '2px solid rgba(139,92,246,0.35)' }}
        >
          <div className="flex items-center gap-4">
            <div
              className="w-11 h-11 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ background: 'rgba(139,92,246,0.1)', border: '1px solid rgba(139,92,246,0.2)' }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <rect x="5" y="2" width="14" height="20" rx="2" ry="2" />
                <line x1="12" y1="18" x2="12.01" y2="18" />
              </svg>
            </div>
            <div>
              <h2 className="font-[family-name:var(--font-display)] font-bold text-lg text-[var(--color-ivory)]">UPI</h2>
              <p className="text-sm text-[var(--color-ash)]">PhonePe · GPay · Paytm · India</p>
            </div>
          </div>
          <div className="flex items-center gap-5">
            <div className="rounded-xl overflow-hidden p-2 flex-shrink-0" style={{ background: '#fff' }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`https://api.qrserver.com/v1/create-qr-code/?size=120x120&data=${encodeURIComponent(UPI_QR_DATA)}&bgcolor=ffffff&color=000000&margin=2`}
                alt={`UPI QR — ${UPI_ID}`}
                width={120}
                height={120}
              />
            </div>
            <div className="flex flex-col gap-3 min-w-0 flex-1">
              <p className="text-sm text-[var(--color-ash)] leading-relaxed">Scan with any UPI app, or send directly to:</p>
              <div
                className="px-3 py-2 rounded-lg text-sm font-[family-name:var(--font-mono)] text-[var(--color-ivory)] truncate"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.09)' }}
              >
                {UPI_ID}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* What your support funds */}
      <div
        className="rounded-2xl border border-[var(--color-slate)] bg-[var(--color-charcoal)] px-7 py-6"
        style={{ borderTop: '2px solid rgba(167,139,250,0.2)' }}
      >
        <h3 className="font-[family-name:var(--font-display)] font-bold text-base text-[var(--color-ivory)] mb-4">
          What your support funds
        </h3>
        <ul className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {[
            ['Mesh R&D', 'Multi-hop routing and store-and-forward reliability'],
            ['Open Source', 'Keeping PeerChat free, auditable, zero-ads — forever'],
            ['Security Reviews', 'Independent cryptographic protocol audits'],
            ['Community', 'Docs, onboarding, and developer tooling'],
          ].map(([title, desc]) => (
            <li key={title} className="flex gap-3 items-start">
              <div className="w-1.5 h-1.5 rounded-full bg-[var(--color-ember)] mt-[9px] flex-shrink-0" />
              <p className="text-sm text-[var(--color-ash)] leading-relaxed">
                <span className="font-semibold text-[var(--color-ivory)]">{title}</span>
                {' — '}{desc}
              </p>
            </li>
          ))}
        </ul>
      </div>
    </SubPageLayout>
  );
}

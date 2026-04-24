import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Changelog — PeerChat',
  description: 'Version history and release notes for PeerChat.',
  alternates: { canonical: 'https://peerchat.mathi.live/changelog' },
};

export default function ChangelogLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}

import type { Metadata } from "next";
import { Space_Grotesk, Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const inter = Inter({
  variable: "--font-body",
  subsets: ["latin"],
  weight: ["300", "400", "500"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  metadataBase: new URL('https://peerchat.mathi.live'),
  title: "PeerChat — Messages that find their way",
  description:
    "Secure, serverless P2P mesh messaging and file transfers. Privacy-first communication that survives without infrastructure. Connect via BLE, WiFi Direct, or Hotspot.",
  keywords: ["P2P messaging", "mesh network", "encrypted chat", "serverless", "WiFi Direct messenger", "BLE messaging", "private communication", "decentralized network"],
  authors: [{ name: "Mathi4Raja" }],
  creator: "Mathi4Raja",
  publisher: "PeerChat",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  openGraph: {
    title: "PeerChat — Messages that find their way",
    description: "Secure, serverless P2P mesh messaging. No servers. No compromises.",
    url: "https://peerchat.mathi.live",
    siteName: "PeerChat",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "PeerChat — P2P Mesh Messaging",
    description: "Serverless communication that finds its way. No infrastructure required.",
    creator: "@mathi4raja",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  alternates: {
    canonical: 'https://peerchat.mathi.live',
  },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "SoftwareApplication",
      "name": "PeerChat",
      "operatingSystem": "Android",
      "applicationCategory": "CommunicationApplication",
      "description": "Peer-to-peer encrypted mesh messaging that works without central servers using Bluetooth and WiFi.",
      "softwareVersion": "1.0.0",
      "downloadUrl": "https://github.com/Mathi4Raja/P2P-app/releases/download/v1.0.0/PeerChat.apk",
      "offers": {
        "@type": "Offer",
        "price": "0",
        "priceCurrency": "USD"
      }
    },
    {
      "@type": "FAQPage",
      "mainEntity": [
        {
          "@type": "Question",
          "name": "What exactly is PeerChat?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "PeerChat is a decentralized, serverless communication platform. It allows users to send encrypted messages and files directly between devices by forming a temporary or stable mesh network using Bluetooth and WiFi."
          }
        },
        {
          "@type": "Question",
          "name": "How does it work without internet?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "PeerChat turns your device into a node in a mesh network. It uses BLE (Bluetooth Low Energy) for discovery and small data packets, and WiFi Direct or WiFi Hotspot for high-speed file transfers."
          }
        },
        {
          "@type": "Question",
          "name": "Is my data secure?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "Yes. Every message is end-to-end encrypted (E2EE) and digitally signed using Sodium (libsodium). Only the intended recipient can read your messages."
          }
        },
        {
          "@type": "Question",
          "name": "How does multi-hop mesh routing work?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "If a destination is out of range, PeerChat can automatically 'hop' the message through intermediate nodes. Each hop is encrypted, so intermediate peers cannot read the content."
          }
        },
        {
          "@type": "Question",
          "name": "Is PeerChat open source?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "Yes, PeerChat is fully open source. You can audit the protocol and the code to verify its security claims on GitHub."
          }
        },
        {
          "@type": "Question",
          "name": "What are the hardware requirements?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "PeerChat is optimized for Android devices with Bluetooth 4.2+ and WiFi capabilities, supporting everything from legacy phones to modern flagships."
          }
        }
      ]
    }
  ]
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <head>
        <meta name="theme-color" content="#0a0a0a" />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </head>
      <body
        className={`${spaceGrotesk.variable} ${inter.variable} ${jetbrainsMono.variable} antialiased bg-[var(--color-ink)] text-[var(--color-ivory)] overflow-x-hidden`}
      >
        {children}

        {/* Noise overlay */}
        <div
          aria-hidden
          className="pointer-events-none fixed inset-0 z-[9999] opacity-[0.03]"
          style={{
            backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='1'/%3E%3C/svg%3E")`,
            backgroundRepeat: 'repeat',
            backgroundSize: '128px 128px',
          }}
        />
      </body>
    </html>
  );
}

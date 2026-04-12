'use client';

import { useEffect, useRef, useCallback } from 'react';
import { motion, useScroll, useSpring } from 'framer-motion';
import dynamic from 'next/dynamic';
import { MeshProvider, useMesh } from '@/lib/mesh-context';
import HeroSection from '@/components/sections/HeroSection';
import FragilitySection from '@/components/sections/FragilitySection';
import SolutionSection from '@/components/sections/SolutionSection';
import EmergenceSection from '@/components/sections/EmergenceSection';
import PropagationSection from '@/components/sections/PropagationSection';
import MessageFlowSection from '@/components/sections/MessageFlowSection';
import InteractionSection from '@/components/sections/InteractionSection';
import DemoSection from '@/components/sections/DemoSection';
import AccessSection from '@/components/sections/AccessSection';
import FaqSection from '@/components/sections/FaqSection';
import FooterSection from '@/components/sections/FooterSection';

// Dynamically import MeshCanvas to avoid SSR issues with Three.js
const MeshCanvas = dynamic(
  () => import('@/components/mesh/MeshCanvas'),
  { ssr: false }
);

function ScrollTracker() {
  const { setScrollProgress, setMousePos } = useMesh();
  const rafRef = useRef<number>(0);

  const handleScroll = useCallback(() => {
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(() => {
      const scrollY = window.scrollY;
      const docHeight = document.documentElement.scrollHeight - window.innerHeight;
      const progress = docHeight > 0 ? scrollY / docHeight : 0;
      setScrollProgress(Math.min(1, Math.max(0, progress)));
    });
  }, [setScrollProgress]);

  const handleMouseMove = useCallback(
    (e: MouseEvent) => {
      setMousePos(
        (e.clientX / window.innerWidth) * 2 - 1,
        -(e.clientY / window.innerHeight) * 2 + 1,
      );
    },
    [setMousePos]
  );

  useEffect(() => {
    window.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('mousemove', handleMouseMove, { passive: true });

    // Trigger initial scroll read
    handleScroll();

    return () => {
      window.removeEventListener('scroll', handleScroll);
      window.removeEventListener('mousemove', handleMouseMove);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [handleScroll, handleMouseMove]);

  return null;
}

function SmoothScroll({ children }: { children: React.ReactNode }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let lenis: any;

    async function initLenis() {
      try {
        const Lenis = (await import('lenis')).default;
        lenis = new Lenis({
          duration: 1.2,
          easing: (t: number) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
          smoothWheel: true,
        });

        function raf(time: number) {
          lenis.raf(time);
          requestAnimationFrame(raf);
        }
        requestAnimationFrame(raf);
      } catch {
        // Lenis not available, native scroll fallback
      }
    }

    initLenis();

    return () => {
      if (lenis) lenis.destroy();
    };
  }, []);

  return <div ref={containerRef}>{children}</div>;
}

function ScrollProgress() {
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, {
    stiffness: 100,
    damping: 30,
    restDelta: 0.001,
  });

  return (
    <motion.div
      className="fixed top-0 left-0 right-0 z-[70] h-[7px] origin-left"
      style={{
        scaleX,
        background:
          'linear-gradient(90deg, #8B5CF6, #7C3AED, #A78BFA, #C4B5FD)',
        boxShadow: '0 0 12px rgba(139,92,246,0.6), 0 0 30px rgba(139,92,246,0.3)',
      }}
    />
  );
}

function PageContent() {
  return (
    <>
      <ScrollTracker />
      <ScrollProgress />

      {/* WebGL mesh - fixed behind content */}
      <div className="fixed inset-0 z-0">
        <MeshCanvas />
      </div>

      {/* Content layer */}
      <SmoothScroll>
        <main className="relative z-10">
          <HeroSection />
          <FragilitySection />
          <SolutionSection />
          <EmergenceSection />
          <PropagationSection />
          <MessageFlowSection />
          <InteractionSection />
          <DemoSection />
          <AccessSection />
          <FaqSection />
          <FooterSection />
        </main>
      </SmoothScroll>
    </>
  );
}

export default function Home() {
  return (
    <MeshProvider>
      <PageContent />
    </MeshProvider>
  );
}

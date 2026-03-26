'use client';

import { createContext, useContext, useRef, useCallback, useState, type ReactNode } from 'react';

export interface MeshNode {
  id: number;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  radius: number;
  energy: number; // 0..1, how "active" this node is
  phase: number;
  connections: number[];
}

export interface Signal {
  id: number;
  fromNode: number;
  toNode: number;
  progress: number; // 0..1
  speed: number;
  trail: { x: number; y: number; z: number; alpha: number }[];
  color: [number, number, number];
  onArrive?: () => void;
}

interface MeshNetworkState {
  nodes: MeshNode[];
  signals: Signal[];
  scrollProgress: number;
  mousePos: { x: number; y: number };
  cascadeActive: boolean;
  phase: 'awakening' | 'fragility' | 'emergence' | 'propagation' | 'interaction' | 'demo' | 'access';
}

interface MeshContextType {
  stateRef: React.MutableRefObject<MeshNetworkState>;
  injectSignal: (fromId: number, toId: number, cascade?: boolean) => void;
  triggerCascade: () => void;
  setScrollProgress: (v: number) => void;
  setMousePos: (x: number, y: number) => void;
  setPhase: (p: MeshNetworkState['phase']) => void;
}

const MeshContext = createContext<MeshContextType | null>(null);

export function useMesh() {
  const ctx = useContext(MeshContext);
  if (!ctx) throw new Error('useMesh must be used inside MeshProvider');
  return ctx;
}

// Generate initial sparse nodes
function createNodes(count: number): MeshNode[] {
  const nodes: MeshNode[] = [];
  for (let i = 0; i < count; i++) {
    const angle = Math.random() * Math.PI * 2;
    const radius = 1.5 + Math.random() * 5;
    nodes.push({
      id: i,
      x: Math.cos(angle) * radius * (0.5 + Math.random()),
      y: (Math.random() - 0.5) * 6,
      z: Math.sin(angle) * radius * (0.5 + Math.random()) - 2,
      vx: (Math.random() - 0.5) * 0.002,
      vy: (Math.random() - 0.5) * 0.002,
      vz: (Math.random() - 0.5) * 0.001,
      radius: 0.04 + Math.random() * 0.03,
      energy: 0,
      phase: Math.random() * Math.PI * 2,
      connections: [],
    });
  }

  // Build connections (sparse — max 3 per node)
  for (let i = 0; i < nodes.length; i++) {
    const dists: { idx: number; dist: number }[] = [];
    for (let j = 0; j < nodes.length; j++) {
      if (i === j) continue;
      const dx = nodes[i].x - nodes[j].x;
      const dy = nodes[i].y - nodes[j].y;
      const dz = nodes[i].z - nodes[j].z;
      dists.push({ idx: j, dist: Math.sqrt(dx * dx + dy * dy + dz * dz) });
    }
    dists.sort((a, b) => a.dist - b.dist);
    const maxConn = 2 + Math.floor(Math.random() * 2); // 2-3
    nodes[i].connections = dists.slice(0, maxConn).filter(d => d.dist < 4).map(d => d.idx);
  }

  return nodes;
}

let signalIdCounter = 0;

export function MeshProvider({ children }: { children: ReactNode }) {
  const stateRef = useRef<MeshNetworkState>({
    nodes: createNodes(28),
    signals: [],
    scrollProgress: 0,
    mousePos: { x: 0, y: 0 },
    cascadeActive: false,
    phase: 'awakening',
  });

  const injectSignal = useCallback((fromId: number, toId: number, cascade = false) => {
    const state = stateRef.current;
    const fromNode = state.nodes[fromId];
    const toNode = state.nodes[toId];
    if (!fromNode || !toNode) return;

    // Energize source node
    fromNode.energy = Math.min(1, fromNode.energy + 0.5);

    const latency = 200 + Math.random() * 600; // ms
    const speed = 1 / (latency / 16.67); // per frame at 60fps

    const sig: Signal = {
      id: signalIdCounter++,
      fromNode: fromId,
      toNode: toId,
      progress: 0,
      speed: speed * 0.5,
      trail: [],
      color: [0.545, 0.361, 0.965], // violet
      onArrive: cascade ? () => {
        // On arrival, propagate to connected nodes
        toNode.energy = Math.min(1, toNode.energy + 0.7);
        const nextTargets = toNode.connections.filter(c => c !== fromId);
        if (nextTargets.length > 0) {
          const delay = 200 + Math.random() * 400;
          setTimeout(() => {
            const target = nextTargets[Math.floor(Math.random() * nextTargets.length)];
            injectSignal(toId, target, Math.random() > 0.4);
          }, delay);
        }
      } : () => {
        toNode.energy = Math.min(1, toNode.energy + 0.5);
      },
    };

    state.signals.push(sig);
  }, []);

  const triggerCascade = useCallback(() => {
    const state = stateRef.current;
    state.cascadeActive = true;

    // Pick a random node and cascade from it
    const startNode = Math.floor(Math.random() * state.nodes.length);
    const node = state.nodes[startNode];
    node.energy = 1;

    node.connections.forEach((connId, i) => {
      setTimeout(() => {
        injectSignal(startNode, connId, true);
      }, i * 150);
    });

    setTimeout(() => {
      state.cascadeActive = false;
    }, 4000);
  }, [injectSignal]);

  const setScrollProgress = useCallback((v: number) => {
    stateRef.current.scrollProgress = v;
  }, []);

  const setMousePos = useCallback((x: number, y: number) => {
    stateRef.current.mousePos = { x, y };
  }, []);

  const setPhase = useCallback((p: MeshNetworkState['phase']) => {
    stateRef.current.phase = p;
  }, []);

  return (
    <MeshContext.Provider value={{
      stateRef,
      injectSignal,
      triggerCascade,
      setScrollProgress,
      setMousePos,
      setPhase,
    }}>
      {children}
    </MeshContext.Provider>
  );
}

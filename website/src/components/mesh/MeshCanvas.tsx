'use client';

import { useRef, useMemo, useCallback } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import { useMesh } from '@/lib/mesh-context';

// ─── Shaders ────────────────────────────────────────────

const bgVertexShader = `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position, 1.0);
}
`;

const bgFragmentShader = `
uniform float uTime;
uniform vec2 uResolution;
uniform float uScrollProgress;

// Simplex-ish noise
vec3 mod289(vec3 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x*34.0)+1.0)*x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
  const vec2 C = vec2(1.0/6.0, 1.0/3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
  vec3 i = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;
  i = mod289(i);
  vec4 p = permute(permute(permute(
    i.z + vec4(0.0, i1.z, i2.z, 1.0))
    + i.y + vec4(0.0, i1.y, i2.y, 1.0))
    + i.x + vec4(0.0, i1.x, i2.x, 1.0));
  float n_ = 0.142857142857;
  vec3 ns = n_ * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);
  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);
  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));
  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
  p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

varying vec2 vUv;

void main() {
  vec2 uv = vUv;
  
  // Base colors
  vec3 ink = vec3(0.035, 0.035, 0.059);
  vec3 charcoal = vec3(0.059, 0.055, 0.094);
  vec3 ember = vec3(0.545, 0.361, 0.965);
  vec3 copper = vec3(0.655, 0.545, 0.980);
  
  // Noise layers
  float n1 = snoise(vec3(uv * 1.5, uTime * 0.03)) * 0.5 + 0.5;
  float n2 = snoise(vec3(uv * 3.0 + 10.0, uTime * 0.05)) * 0.5 + 0.5;
  float n3 = snoise(vec3(uv * 0.8 + 5.0, uTime * 0.02 + uScrollProgress * 0.5)) * 0.5 + 0.5;
  
  // Gradient base
  vec3 color = mix(ink, charcoal, n1 * 0.5 + uv.y * 0.2);
  
  // Warm accent zones
  float warmZone = smoothstep(0.55, 0.65, n2) * smoothstep(0.5, 0.6, n3);
  color += ember * warmZone * 0.04;
  color += copper * n3 * 0.02;
  
  // Vignette
  float vignette = 1.0 - length((uv - 0.5) * 1.4);
  vignette = smoothstep(0.0, 0.7, vignette);
  color *= 0.7 + vignette * 0.3;
  
  // Depth fog driven by scroll
  float fogAmount = smoothstep(0.0, 1.0, uScrollProgress) * 0.1;
  color = mix(color, charcoal, fogAmount);
  
  gl_FragColor = vec4(color, 1.0);
}
`;

// ─── Background Plane ───────────────────────────────────

function BackgroundPlane() {
  const meshRef = useRef<THREE.Mesh>(null);
  const { stateRef } = useMesh();

  const uniforms = useMemo(() => ({
    uTime: { value: 0 },
    uResolution: { value: new THREE.Vector2(1, 1) },
    uScrollProgress: { value: 0 },
  }), []);

  useFrame(({ clock }) => {
    uniforms.uTime.value = clock.getElapsedTime();
    uniforms.uScrollProgress.value = stateRef.current.scrollProgress;
  });

  return (
    <mesh ref={meshRef} frustumCulled={false} renderOrder={-1}>
      <planeGeometry args={[2, 2]} />
      <shaderMaterial
        vertexShader={bgVertexShader}
        fragmentShader={bgFragmentShader}
        uniforms={uniforms}
        depthTest={false}
        depthWrite={false}
      />
    </mesh>
  );
}

// ─── Node Geometry (Instanced) ──────────────────────────

function MeshNodes() {
  const { stateRef, injectSignal } = useMesh();
  const instancedRef = useRef<THREE.InstancedMesh>(null);
  const glowRef = useRef<THREE.InstancedMesh>(null);
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const nodeCount = stateRef.current.nodes.length;

  useFrame(({ clock }) => {
    const time = clock.getElapsedTime();
    if (!instancedRef.current || !glowRef.current) return;
    const nodes = stateRef.current.nodes;
    const scroll = stateRef.current.scrollProgress;

    // How many nodes are visible depends on scroll
    const visibleRatio = Math.min(1, scroll * 5 + 0.15); // start with ~15% visible

    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];

      // Drift
      node.x += node.vx;
      node.y += node.vy;
      node.z += node.vz;

      // Soft boundary
      if (Math.abs(node.x) > 7) node.vx *= -0.8;
      if (Math.abs(node.y) > 4) node.vy *= -0.8;
      if (Math.abs(node.z) > 5) node.vz *= -0.8;

      // Energy decay
      node.energy *= 0.97;

      const visible = (i / nodes.length) < visibleRatio;
      const scale = visible
        ? (node.radius + node.energy * 0.06) * (1 + Math.sin(time * 0.5 + node.phase) * 0.1)
        : 0.001;

      dummy.position.set(node.x, node.y, node.z);
      dummy.scale.setScalar(scale);
      dummy.updateMatrix();
      instancedRef.current.setMatrixAt(i, dummy.matrix);

      // Glow — bigger, transparent
      const glowScale = visible ? scale * (3 + node.energy * 8) : 0.001;
      dummy.scale.setScalar(glowScale);
      dummy.updateMatrix();
      glowRef.current.setMatrixAt(i, dummy.matrix);

      // Color based on energy
      const color = new THREE.Color();
      color.setRGB(
        0.45 + node.energy * 0.1,
        0.36 + node.energy * 0.1,
        0.75 + node.energy * 0.22
      );
      instancedRef.current.setColorAt(i, color);

      const glowColor = new THREE.Color();
      glowColor.setRGB(
        0.545 * node.energy,
        0.361 * node.energy,
        0.965 * node.energy
      );
      glowRef.current.setColorAt(i, glowColor);
    }

    instancedRef.current.instanceMatrix.needsUpdate = true;
    instancedRef.current.instanceColor!.needsUpdate = true;
    glowRef.current.instanceMatrix.needsUpdate = true;
    glowRef.current.instanceColor!.needsUpdate = true;
  });

  return (
    <>
      {/* Core nodes */}
      <instancedMesh ref={instancedRef} args={[undefined, undefined, nodeCount]}>
        <sphereGeometry args={[1, 12, 12]} />
        <meshBasicMaterial toneMapped={false} />
      </instancedMesh>

      {/* Glow halos */}
      <instancedMesh ref={glowRef} args={[undefined, undefined, nodeCount]}>
        <sphereGeometry args={[1, 8, 8]} />
        <meshBasicMaterial transparent opacity={0.06} toneMapped={false} />
      </instancedMesh>
    </>
  );
}

// ─── Connection Lines ───────────────────────────────────

function ConnectionLines() {
  const { stateRef } = useMesh();
  const linesRef = useRef<THREE.Group>(null);

  const lineGeometries = useMemo(() => {
    const geos: { from: number; to: number }[] = [];
    const nodes = stateRef.current.nodes;
    const seen = new Set<string>();
    for (const node of nodes) {
      for (const connId of node.connections) {
        const key = [Math.min(node.id, connId), Math.max(node.id, connId)].join('-');
        if (!seen.has(key)) {
          seen.add(key);
          geos.push({ from: node.id, to: connId });
        }
      }
    }
    return geos;
  }, [stateRef]);

  useFrame(() => {
    if (!linesRef.current) return;
    const nodes = stateRef.current.nodes;
    const scroll = stateRef.current.scrollProgress;
    const visibleRatio = Math.min(1, scroll * 5 + 0.15);

    linesRef.current.children.forEach((child, idx) => {
      const line = child as THREE.Line;
      const geo = lineGeometries[idx];
      if (!geo) return;

      const fromNode = nodes[geo.from];
      const toNode = nodes[geo.to];
      const fromVisible = (geo.from / nodes.length) < visibleRatio;
      const toVisible = (geo.to / nodes.length) < visibleRatio;

      if (fromVisible && toVisible) {
        const positions = line.geometry.attributes.position as THREE.BufferAttribute;
        
        // Slightly curved line via a midpoint offset
        const mx = (fromNode.x + toNode.x) / 2 + Math.sin(fromNode.phase) * 0.15;
        const my = (fromNode.y + toNode.y) / 2 + Math.cos(toNode.phase) * 0.15;
        const mz = (fromNode.z + toNode.z) / 2;

        positions.setXYZ(0, fromNode.x, fromNode.y, fromNode.z);
        positions.setXYZ(1, mx, my, mz);
        positions.setXYZ(2, toNode.x, toNode.y, toNode.z);
        positions.needsUpdate = true;

        // Opacity based on energy of connected nodes
        const energy = Math.max(fromNode.energy, toNode.energy);
        const mat = line.material as THREE.LineBasicMaterial;
        mat.opacity = 0.04 + energy * 0.35;
      } else {
        const mat = line.material as THREE.LineBasicMaterial;
        mat.opacity = 0;
      }
    });
  });

  return (
    <group ref={linesRef}>
      {lineGeometries.map((geo, i) => (
        <line key={i}>
          <bufferGeometry>
            <bufferAttribute
              attach="attributes-position"
              args={[new Float32Array(9), 3]}
            />
          </bufferGeometry>
          <lineBasicMaterial
            color="#A78BFA"
            transparent
            opacity={0.04}
            toneMapped={false}
          />
        </line>
      ))}
    </group>
  );
}

// ─── Signal Particles ───────────────────────────────────

function SignalParticles() {
  const { stateRef } = useMesh();
  const groupRef = useRef<THREE.Group>(null);

  // Pre-create max signal meshes
  const maxSignals = 30;
  const signalRefs = useRef<(THREE.Mesh | null)[]>([]);
  const trailRefs = useRef<(THREE.Points | null)[]>([]);

  useFrame(() => {
    const signals = stateRef.current.signals;
    const nodes = stateRef.current.nodes;

    for (let i = 0; i < maxSignals; i++) {
      const mesh = signalRefs.current[i];
      const trail = trailRefs.current[i];
      if (!mesh) continue;

      if (i < signals.length) {
        const sig = signals[i];
        const fromNode = nodes[sig.fromNode];
        const toNode = nodes[sig.toNode];

        if (!fromNode || !toNode) continue;

        // Advance
        sig.progress += sig.speed;

        // Curved interpolation with midpoint
        const mx = (fromNode.x + toNode.x) / 2 + Math.sin(fromNode.phase) * 0.15;
        const my = (fromNode.y + toNode.y) / 2 + Math.cos(toNode.phase) * 0.15;
        const mz = (fromNode.z + toNode.z) / 2;

        const t = sig.progress;
        // Quadratic Bezier
        const it = 1 - t;
        const x = it * it * fromNode.x + 2 * it * t * mx + t * t * toNode.x;
        const y = it * it * fromNode.y + 2 * it * t * my + t * t * toNode.y;
        const z = it * it * fromNode.z + 2 * it * t * mz + t * t * toNode.z;

        mesh.position.set(x, y, z);
        mesh.visible = true;

        // Stretch in direction of travel
        const dx = toNode.x - fromNode.x;
        const dy = toNode.y - fromNode.y;
        const dirLen = Math.sqrt(dx * dx + dy * dy) || 1;
        const stretchX = 1 + (sig.speed * 20);
        mesh.scale.set(stretchX * 0.06, 0.06, 0.06);
        mesh.lookAt(toNode.x, toNode.y, toNode.z);

        // Trail
        sig.trail.push({ x, y, z, alpha: 1 });
        if (sig.trail.length > 12) sig.trail.shift();
        sig.trail.forEach(p => { p.alpha *= 0.88; });

        if (trail) {
          const trailPos = trail.geometry.attributes.position as THREE.BufferAttribute;
          for (let j = 0; j < 12; j++) {
            const tp = sig.trail[j];
            if (tp) {
              trailPos.setXYZ(j, tp.x, tp.y, tp.z);
            } else {
              trailPos.setXYZ(j, x, y, z);
            }
          }
          trailPos.needsUpdate = true;
          trail.visible = true;
        }

        // Arrived
        if (sig.progress >= 1) {
          sig.onArrive?.();
        }
      } else {
        mesh.visible = false;
        if (trail) trail.visible = false;
      }
    }

    // Clean up completed signals
    stateRef.current.signals = signals.filter(s => s.progress < 1);
  });

  return (
    <group ref={groupRef}>
      {Array.from({ length: maxSignals }).map((_, i) => (
        <group key={i}>
          <mesh ref={el => { signalRefs.current[i] = el; }} visible={false}>
            <sphereGeometry args={[1, 8, 8]} />
            <meshBasicMaterial color="#8B5CF6" toneMapped={false} transparent opacity={0.9} />
          </mesh>
          <points ref={(el: any) => { trailRefs.current[i] = el; }} visible={false}>
            <bufferGeometry>
              <bufferAttribute
                attach="attributes-position"
                args={[new Float32Array(36), 3]}
              />
            </bufferGeometry>
            <pointsMaterial
              color="#8B5CF6"
              size={0.03}
              transparent
              opacity={0.4}
              toneMapped={false}
              sizeAttenuation
            />
          </points>
        </group>
      ))}
    </group>
  );
}

// ─── Mouse Interaction ──────────────────────────────────

function MouseInteraction() {
  const { stateRef, injectSignal } = useMesh();
  const { camera, raycaster, pointer } = useThree();
  const plane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 0, 1), 2), []);
  const intersectPoint = useMemo(() => new THREE.Vector3(), []);
  const lastClickTime = useRef(0);

  useFrame(() => {
    const nodes = stateRef.current.nodes;
    const mouse = stateRef.current.mousePos;

    // Convert mouse to 3D
    raycaster.setFromCamera(new THREE.Vector2(mouse.x, mouse.y), camera);
    raycaster.ray.intersectPlane(plane, intersectPoint);

    // Subtle node attraction/repulsion near mouse
    for (const node of nodes) {
      const dx = intersectPoint.x - node.x;
      const dy = intersectPoint.y - node.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < 2 && dist > 0.1) {
        const force = 0.0003 / (dist * dist);
        node.vx += dx * force;
        node.vy += dy * force;
        // Subtle energy boost
        node.energy = Math.min(1, node.energy + 0.002 / dist);
      }
    }
  });

  return null;
}

// ─── Camera Controller ──────────────────────────────────

function CameraController() {
  const { stateRef } = useMesh();
  const { camera } = useThree();

  useFrame(() => {
    const scroll = stateRef.current.scrollProgress;
    const mouse = stateRef.current.mousePos;

    // Slow camera drift based on scroll
    const targetY = -scroll * 2;
    const targetZ = 6 - scroll * 0.5;

    camera.position.y += (targetY - camera.position.y) * 0.02;
    camera.position.z += (targetZ - camera.position.z) * 0.02;

    // Subtle mouse parallax
    camera.position.x += (mouse.x * 0.3 - camera.position.x) * 0.02;

    camera.lookAt(0, camera.position.y, 0);
  });

  return null;
}

// ─── Auto Signals ───────────────────────────────────────

function AutoSignals() {
  const { stateRef, injectSignal } = useMesh();
  const lastSignalTime = useRef(0);

  useFrame(({ clock }) => {
    const time = clock.getElapsedTime();
    const scroll = stateRef.current.scrollProgress;

    // Auto-send signals periodically — rate increases with scroll
    const interval = Math.max(0.8, 3 - scroll * 4);
    if (time - lastSignalTime.current > interval) {
      lastSignalTime.current = time;
      const nodes = stateRef.current.nodes;
      const visibleCount = Math.max(2, Math.floor(nodes.length * Math.min(1, scroll * 5 + 0.15)));

      const fromIdx = Math.floor(Math.random() * visibleCount);
      const node = nodes[fromIdx];
      if (node && node.connections.length > 0) {
        const toIdx = node.connections[Math.floor(Math.random() * node.connections.length)];
        if (toIdx < visibleCount) {
          injectSignal(fromIdx, toIdx, scroll > 0.3);
        }
      }
    }
  });

  return null;
}

// ─── Main Scene ─────────────────────────────────────────

function MeshScene() {
  return (
    <>
      <BackgroundPlane />
      <CameraController />
      <MouseInteraction />
      <MeshNodes />
      <ConnectionLines />
      <SignalParticles />
      <AutoSignals />
    </>
  );
}

// ─── Exported Canvas Wrapper ────────────────────────────

export default function MeshCanvas() {
  const { setMousePos, injectSignal, stateRef } = useMesh();

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    const x = (e.clientX / window.innerWidth) * 2 - 1;
    const y = -(e.clientY / window.innerHeight) * 2 + 1;
    setMousePos(x, y);
  }, [setMousePos]);

  const handleClick = useCallback((e: React.MouseEvent) => {
    // Find nearest visible node and inject signal
    const nodes = stateRef.current.nodes;
    const scroll = stateRef.current.scrollProgress;
    const visibleCount = Math.max(2, Math.floor(nodes.length * Math.min(1, scroll * 5 + 0.15)));

    const randomFrom = Math.floor(Math.random() * visibleCount);
    const node = nodes[randomFrom];
    if (node && node.connections.length > 0) {
      const toIdx = node.connections[Math.floor(Math.random() * node.connections.length)];
      injectSignal(randomFrom, toIdx, true);
    }
  }, [injectSignal, stateRef]);

  return (
    <div
      className="mesh-canvas-wrap"
      onPointerMove={handlePointerMove}
      onClick={handleClick}
    >
      <Canvas
        camera={{ position: [0, 0, 6], fov: 60 }}
        dpr={[1, 1.5]}
        gl={{ antialias: true, alpha: false, powerPreference: 'high-performance' }}
        style={{ background: '#09090f' }}
      >
        <MeshScene />
      </Canvas>
    </div>
  );
}

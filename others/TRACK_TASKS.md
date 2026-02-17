# Mesh Routing Implementation Phases

## Phase 1: Dependencies and Infrastructure
- [x] Fix `pubspec.yaml` formatting issues
- [x] Add required dependencies (`sodium_libs`, `uuid`)
- [x] Verify dependency installation

## Phase 2: Data Layer Implementation
- [x] Create Database Schema Extensions (Message Queue, Routes, Dedup Cache, Blocked Peers, Pending Acks)
- [x] Implement `DBService` extensions
- [x] Create Data Models (`MeshMessage`, `Route`, `QueuedMessage`, `RouteRequest`, `RouteResponse`)

## Phase 3: Cryptography and Core Services
- [ ] Implement/Verify `SignatureVerifier` (Sodium crypto_sign)
- [ ] Implement/Verify `MessageManager` (Encryption/Decryption/Signing)
- [ ] Implement/Verify `DeduplicationCache`

## Phase 4: Routing Logic
- [ ] Implement `RouteManager` (Route discovery, table management)
- [ ] Implement `MessageQueue` (Store-and-forward logic)
- [ ] Implement `MeshRouterService` main coordinator

## Phase 5: UI Integration & Testing
- [ ] Create routing debug UI
- [ ] Integrate with existing Chat UI
- [ ] Test multi-hop scenarios

## Phase 6: Project Cleanup
- [x] Move documentation files to `others/`
- [x] Update `.gitignore`

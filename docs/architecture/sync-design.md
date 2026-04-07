# Cross-Device Sync Architecture Design

**Document Version:** 1.0  
**Status:** Design Phase  
**Last Updated:** 2026-04-07  
**Related:** [Mac Audio Capture Research](../research/mac-audio-capture-evaluation.md), [Whisper Models Evaluation](../research/whisper-models-evaluation.md)

---

## Executive Summary

This document outlines the architecture for cross-device profile synchronization between Mac (primary implementation) and Android (future platform) applications. The design ensures that **the current Mac implementation supports this extensibility without breaking changes**, using abstractions that can accommodate both platforms.

**Key Design Principles:**
- **Pluggable Architecture:** Current storage implementation remains unchanged; sync is additive
- **Eventual Consistency:** Offline-first design with conflict resolution
- **Platform-Agnostic:** Sync layer abstracts platform-specific storage
- **Privacy-First:** Encryption at rest and in transit
- **Incremental Adoption:** Sync can be enabled/disabled per user

---

## Table of Contents

1. [System Architecture Overview](#1-system-architecture-overview)
2. [Data Model](#2-data-model)
3. [Sync Protocol Design](#3-sync-protocol-design)
4. [Storage Abstraction Layer](#4-storage-abstraction-layer)
5. [Security & Privacy](#5-security--privacy)
6. [API Contract](#6-api-contract)
7. [Implementation Roadmap](#7-implementation-roadmap)

---

## 1. System Architecture Overview

### 1.1 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          CLOUD SYNC SERVICE                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │
│  │  Sync Gateway   │  │  Conflict       │  │  Profile Store          │ │
│  │  (API Gateway)  │  │  Resolver       │  │  (Encrypted)            │ │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────────────┘ │
│           │                    │                                        │
│  ┌─────────────────┐  ┌─────────────────┐                              │
│  │  Auth Service   │  │  Sync History   │                              │
│  │  (OAuth 2.0)    │  │  (Audit Trail)  │                              │
│  └─────────────────┘  └─────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────┘
            │                                        │
            │ HTTPS / WebSocket                      │ HTTPS / WebSocket
            │ (TLS 1.3)                              │ (TLS 1.3)
            │                                        │
     ┌──────┴──────┐                          ┌────┴────┐
     │             │                          │         │
┌────┴────┐   ┌────┴────┐                ┌────┴────┐ ┌─┴──────┐
│  Mac    │   │  Mac    │                │ Android │ │ Android│
│  App    │   │  App    │                │  App    │ │  App   │
│(Primary)│   │(Future) │                │(Future) │ │(Future)│
└────┬────┘   └────┬────┘                └────┬────┘ └────┬───┘
     │             │                          │           │
┌────┴─────────────┴─┐                  ┌─────┴───────────┴───┐
│   Sync Adapter     │                  │   Sync Adapter      │
│   (Rust/Swift)     │                  │   (Rust/Kotlin)     │
│ ┌───────────────┐  │                  │  ┌───────────────┐  │
│ │ Sync Engine   │  │                  │  │ Sync Engine   │  │
│ │ - CRDT-based  │  │                  │  │ - CRDT-based  │  │
│ │ - Offline Q   │  │                  │  │ - Offline Q   │  │
│ └───────┬───────┘  │                  │  └───────┬───────┘  │
│         │          │                  │          │          │
│ ┌───────┴───────┐  │                  │  ┌───────┴───────┐  │
│ │ Sync Abstraction│                  │  │ Sync Abstraction│  │
│ │ Interface       │  │                  │  │ Interface      │  │
│ └───────┬───────┘  │                  │  └───────┬───────┘  │
│         │          │                  │          │          │
│ ┌───────┴───────┐  │                  │  ┌───────┴───────┐  │
│ │ Platform Store │  │                  │  │ Platform Store │  │
│ │ - Core Data    │  │                  │  │ - SQLite Room  │  │
│ │ - File System  │  │                  │  │ - Internal     │  │
│ └────────────────  │                  │  └────────────────  │  │
└────────────────────┘                  └───────────────────────┘
```

### 1.2 Component Breakdown

| Component | Technology | Responsibility |
|-----------|------------|----------------|
| **Sync Engine** | Rust (cross-platform) | CRDT operations, offline queue, conflict resolution |
| **Sync Adapter** | Platform bindings (Swift/Kotlin) | Device-specific implementation, event handling |
| **Sync Service** | Cloud (AWS/GCP/Azure) | Auth, storage, history, push notifications |
| **Storage Abstraction** | Interface/protocol | Platform-agnostic storage operations |

### 1.3 Data Flow

#### Initial Sync (Device Pairing)
```
┌──────┐                           ┌──────────────┐
│ User │── Sign In (OAuth) ───────▶│ Auth Service │
└──────┘                           └──────┬───────┘
                                          │ Token
┌──────┐                           ┌──────┴───────┐
│Server│◀─ Request Profile ───────│   Mac App    │
└──┬───┘                           └──────────────┘
   │                                     │
   │  Profile Snapshot + Encrypted Data  │
   └────────────────────────────────────▶│
                                        │
                              ┌─────────┴─────────┐
                              │ Decrypt + Store   │
                              │ (First Sync)      │
                              └───────────────────┘
```

#### Regular Sync (Bi-directional)
```
┌──────────┐     Change Event       ┌─────────────┐
│ Mac User │─── Edit Preferences ──▶│ Sync Engine │
└──────────┘                        └──────┬──────┘
                                           │ Generate Delta
                              ┌────────────┴────────────┐
                              │ Calculate CRDT changes  │
                              │ Queue for sync          │
                              └────────────┬────────────┘
                                           │ Upload
┌──────────┐                    ┌──────────┴──────────┐
│ Sync Svc │◀─ Encrypted Delta ─│    Cloud Service    │
└───┬──────┘                    └─────────────────────┘
    │
    │ Push Notification (FCM/APNs)
    ▼
┌──────────┐
│ Android  │── Fetch Delta ───────▶ Download & Decrypt
│  Device  │── Apply CRDT Ops ────▶ Resolve if needed
│          │── Update Local Store ─▶ Notify User
└──────────┘
```

---

## 2. Data Model

### 2.1 Profile Entity

The profile is the root entity that defines a user's cross-device identity and syncable data.

```
┌─────────────────────────────────────────────────────────────────────┐
│                           USER PROFILE                               │
├───────────────┬─────────────────────────────────────────────────────┤
│ profile_id    │ UUID (primary identifier)                           │
│ user_id       │ OAuth sub claim (user identity)                    │
│ created_at    │ ISO 8601 timestamp                                  │
│ updated_at    │ ISO 8601 timestamp (CRDT logical clock)             │
│ version       │ Integer (schema version)                            │
│ devices       │ Array<DeviceRecord>                                 │
├───────────────┴─────────────────────────────────────────────────────┤
│                         SYNCABLE ENTITIES                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐ │
│  │   Preferences    │  │ Custom Vocabulary│  │  Transcription    │ │
│  │                  │  │                  │  │     History       │ │
│  │ • Settings       │  │ • User words     │  │ • Recent entries  │ │
│  │ • UI config      │  │ • Corrections    │  │ • Favorites       │ │
│  │ • Hotkeys        │  │ • Phrases        │  │ • Usage stats     │ │
│  │ • Audio config   │  │ • Categories     │  │ • Tags            │ │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬──────────┘ │
│           │                     │                     │            │
│           └─────────────────────┴─────────────────────┘            │
│                          (Each has CRDT metadata)                    │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Entity Schemas

#### Profile Root Schema
```typescript
interface Profile {
  profile_id: string;           // UUID v4
  user_id: string;              // OAuth sub claim
  created_at: string;           // ISO 8601
  updated_at: string;           // CRDT hybrid logical timestamp
  version: number;              // Schema version (current: 1)
  
  // Embedded entities
  preferences: Preferences;
  vocabulary: CustomVocabulary;
  history: TranscriptionHistory;
  devices: DeviceRecord[];
  
  // CRDT metadata
  crdt_meta: CRDTMetadata;
}
```

#### Preferences Schema
```typescript
interface Preferences {
  // Appearance
  theme: "system" | "light" | "dark";
  font_size: "small" | "medium" | "large";
  show_preview: boolean;
  
  // Audio
  input_device: string | null;     // Device ID
  sample_rate: 16000 | 44100 | 48000;
  noise_reduction: boolean;
  
  // Shortcuts
  hotkey: HotkeyConfig;
  
  // Transcription
  insert_mode: "inline" | "clipboard" | "both";
  auto_punctuation: boolean;
  language: string;                // ISO 639-1 code
  model_quality: "tiny" | "base" | "small" | "medium";
  
  // Privacy
  store_history: boolean;
  local_encryption: boolean;
}

interface HotkeyConfig {
  // Platform-agnostic key representation
  modifiers: ("cmd" | "alt" | "ctrl" | "shift")[];  // Mac
  // modifiers: ("ctrl" | "alt" | "shift" | "meta")[]; // Android
  key: string;                    // Single character or key name
}
```

#### Custom Vocabulary Schema
```typescript
interface CustomVocabulary {
  // CRDT map: word -> metadata
  words: Map<string, VocabularyEntry>;
  categories: Category[];
}

interface VocabularyEntry {
  text: string;                   // The actual word/phrase
  pronunciation_hint?: string;    // For phonetic matching
  category_ids: string[];         // Reference to categories
  frequency: number;              // Usage frequency for ranking
  created_at: string;
  updated_at: string;
  
  // CRDT metadata for this entry
  crdt_meta: {
    hlc: HybridLogicalClock;      // Logical timestamp
    peer_id: string;              // Device that created it
    version: number;              // Entry version
  };
}

interface Category {
  id: string;
  name: string;
  color: string;                  // Hex color code
  icon?: string;                  // Icon identifier
  priority: number;               // Category ordering
}
```

#### Transcription History Schema
```typescript
interface TranscriptionHistory {
  // Recent entries (last 100 by default, configurable)
  recent: TranscriptionEntry[];
  
  // Statistics for ML-based improvements
  usage_stats: UsageStatistics;
}

interface TranscriptionEntry {
  id: string;                     // UUID
  text: string;                   // Transcribed text
  timestamp: string;              // When transcribed
  duration_ms: number;            // Audio duration
  confidence: number;             // Model confidence score
  language: string;               // Detected language
  tags: string[];                 // User tags
  is_favorite: boolean;
  
  // Not synced - local only (audio file)
  local_audio_path?: string;      // Platform-specific path
}

interface UsageStatistics {
  total_transcriptions: number;
  total_duration_ms: number;
  by_language: Map<string, number>;
  daily_counts: Map<string, number>;  // Date -> count
}
```

### 2.3 Device Record

```typescript
interface DeviceRecord {
  device_id: string;              // Stable device identifier
  device_type: "mac" | "ios" | "android" | "windows" | "linux";
  device_name: string;            // User-configurable name
  model_info: string;             // e.g., "MacBook Pro (14-inch)"
  
  // Sync state
  last_sync_at: string;           // Last successful sync
  sync_version: number;           // Current sync protocol version
  
  // Capabilities
  supports_offline: boolean;
  encryption_version: number;     // Key derivation version
  
  // Status
  is_active: boolean;
  is_primary: boolean;            // Primary device (used for resets)
}
```

### 2.4 CRDT Metadata

```typescript
interface CRDTMetadata {
  // Hybrid Logical Clock for ordering
  hlc: HybridLogicalClock;
  
  // Vector clock for causal relationships
  vector_clock: Map<string, number>;
  
  // Tombstone data (for deletions)
  tombstones: Tombstone[];
  
  // Conflict resolution strategy per field
  resolution_strategy: Map<string, ResolutionStrategy>;
}

interface HybridLogicalClock {
  wall_time: number;              // Physical timestamp (ms since epoch)
  logical: number;                // Logical counter for same-millisecond events
  peer_id: string;                // Unique peer identifier
}

interface Tombstone {
  entity_id: string;              // ID of deleted entity
  deleted_at: HybridLogicalClock; // When deleted
  reason: string;                 // Optional: why deleted
}

type ResolutionStrategy = 
  | "last-write-wins"    // Simple timestamp comparison
  | "merge"              // Combine values (for arrays)
  | "custom";            // Custom logic per entity type
```

---

## 3. Sync Protocol Design

### 3.1 Protocol Overview

**Name:** WisprSync Protocol v1  
**Base:** HTTPS + WebSocket (real-time)  
**Sync Model:** Delta-based with CRDT operations  
**Conflict Strategy:** CRDT merge with field-level resolution

### 3.2 Sync Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Full Sync** | Complete profile snapshot | First sync, device reset, corruption recovery |
| **Delta Sync** | Only changed operations | Regular periodic sync, app startup |
| **Real-time** | WebSocket push | Active session, multi-device live editing |
| **Offline Queue** | Buffered operations | No connectivity, batched on restore |

### 3.3 Delta Sync Protocol

```typescript
// Sync Request
interface SyncRequest {
  device_id: string;
  profile_id: string;
  sync_token: SyncToken;          // Checkpoint from last sync
  
  // Outgoing changes from this device
  operations: CRDTOperation[];
  
  // Request parameters
  request_full_sync: boolean;     // Force full sync if true
}

// Sync Response
interface SyncResponse {
  sync_token: SyncToken;          // New checkpoint
  
  // Incoming changes from server
  operations: CRDTOperation[];
  
  // Server-side conflicts that need resolution
  conflicts: Conflict[];
  
  // Status
  status: "success" | "partial" | "conflict" | "error";
  next_sync_at?: string;          // Suggested next sync time
}

// CRDT Operation Types
interface CRDTOperation {
  op_id: string;                  // Unique operation ID
  op_type: "insert" | "update" | "delete" | "merge";
  
  // Target entity
  entity_type: string;            // e.g., "preferences", "vocabulary"
  entity_id: string;              // Entity UUID
  field_path: string;             // Dot-notation path to field
  
  // Payload
  value?: unknown;                // New value (for insert/update)
  old_value?: unknown;            // Previous value (for validation)
  
  // CRDT timestamp
  hlc: HybridLogicalClock;
  
  // Source
  peer_id: string;                // Device that created the op
  created_at: string;             // ISO timestamp (for debugging)
}

// Sync Token (opaque to client)
interface SyncToken {
  version: number;                // Token version
  checkpoint: string;             // Server-side checkpoint
  hlc: HybridLogicalClock;        // Client's HLC at sync time
  signature: string;              // HMAC for integrity
}
```

### 3.4 Conflict Resolution

#### CRDT Strategy Table

| Entity | Field | Strategy | Rationale |
|--------|-------|----------|-----------|
| **Preferences** | theme | Last-write-wins | User preference |
| **Preferences** | hotkey | Last-write-wins | User preference |
| **Preferences** | language | Last-write-wins | User preference |
| **Vocabulary** | words | CRDT Set merge | Union of additions |
| **Vocabulary** | word.deleted | Tombstone + LWW | Deletion is final |
| **Vocabulary** | word.frequency | Additive merge | Sum of frequencies |
| **History** | recent | LWW + capacity | Replace, keep N entries |
| **History** | stats | Additive merge | Cumulative statistics |

#### Conflict Resolution Flow

```
Device A changes 'theme' to 'dark' ─┐
                                    ├──┐
Device B changes 'theme' to 'light' ─┘  │
                                          │
                                    [Cloud Server]
                                          │
                                    Detects Conflict
                                          │
                                    HLC Comparison:
                                    - A: hlc=100:2:device-a
                                    - B: hlc=100:1:device-b
                                          │
                                    Resolve: HLC 100:2 > 100:1
                                          │
                                    Winner: Device A ('dark')
                                          │
                                    ┌─────┴─────┐
                            Apply: A's value      Record: B's
                                 to all           value in
                                                conflict log
```

### 3.5 Offline Support

```
┌─────────────────────────────────────────────────────────────────┐
│                     OFFLINE SYNC STATE MACHINE                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────┐    Write Op    ┌──────────┐    Network Up      │
│   │  Online  │──────────────▶ │  Queue   │──────────────┐     │
│   │  Sync    │                  │  Buffer  │              │     │
│   └──────────┘◀──────────────── └──────────┘◀─────────────┘     │
│        │                            │                           │
│        │ Success                    │ Retry                     │
│        ▼                            ▼                           │
│   ┌──────────┐    Max Retries   ┌──────────┐                   │
│   │  Sync'd  │◀──────────────── │  Failed  │                   │
│   │  State   │                  │  State   │                   │
│   └──────────┘                  └──────────┘                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Offline Queue Properties:**
- Durability: Persisted to local storage immediately
- Ordering: FIFO with priority for user-visible changes
- Compaction: Adjacent operations to same field are merged
- Retry: Exponential backoff with max 5 attempts
- Conflict: On retry success, client re-applies server operations

### 3.6 Real-Time Sync (WebSocket)

**Connection Lifecycle:**
```
1. POST /sync/poll → Check if realtime needed (or HTTP/2 SSE)
2. If active on multiple devices → Upgrade to WebSocket
3. WebSocket: wss://api.speakr.dev/v1/sync/realtime
4. Authenticate with sync_token
5. Exchange heartbeat every 30s
6. Push operations immediately on change
```

**WebSocket Message Types:**
```typescript
// Client → Server
type ClientMessage = 
  | { type: "operation"; op: CRDTOperation }
  | { type: "ping"; timestamp: number }
  | { type: "ack"; op_id: string };

// Server → Client
type ServerMessage = 
  | { type: "operation"; ops: CRDTOperation[] }
  | { type: "conflict"; conflict: Conflict }
  | { type: "pong"; timestamp: number }
  | { type: "refresh"; reason: string };
```

---

## 4. Storage Abstraction Layer

### 4.1 Architecture Goal

The storage abstraction layer decouples the sync engine from platform-specific storage implementations, enabling:
- **Single Sync Engine:** Same Rust code on Mac and Android
- **Platform Storage:** Each platform uses native storage (Core Data, SQLite, etc.)
- **Testability:** In-memory storage for unit tests
- **Future Extensibility:** New platforms only implement the interface

### 4.2 Abstraction Interface

```rust
// Rust Core (Sync Engine)
pub trait ProfileStorage: Send + Sync {
    /// Profile lifecycle
    fn create_profile(&self, profile: Profile) -> Result<ProfileId, StorageError>;
    fn load_profile(&self, id: ProfileId) -> Result<Profile, StorageError>;
    fn save_profile(&self, profile: &Profile) -> Result<(), StorageError>;
    fn delete_profile(&self, id: ProfileId) -> Result<(), StorageError>;
    
    /// Entity operations (CRUD with CRDT)
    fn insert_entity(
        &self,
        entity_type: &str,
        id: EntityId,
        value: &Value,
        metadata: CRDTMetadata
    ) -> Result<(), StorageError>;
    
    fn update_entity(
        &self,
        entity_type: &str,
        id: EntityId,
        path: &str,
        value: &Value,
        metadata: CRDTMetadata
    ) -> Result<(), StorageError>;
    
    fn delete_entity(
        &self,
        entity_type: &str,
        id: EntityId,
        metadata: CRDTMetadata
    ) -> Result<(), StorageError>;
    
    fn get_entity(
        &self,
        entity_type: &str,
        id: EntityId
    ) -> Result<Option<Entity>, StorageError>;
    
    /// Sync-specific operations
    fn get_changes_since(
        &self,
        checkpoint: &SyncCheckpoint
    ) -> Result<Vec<CRDTOperation>, StorageError>;
    
    fn apply_operations(
        &self,
        operations: &[CRDTOperation]
    ) -> Result<ApplyResult, StorageError>;
    
    fn get_sync_checkpoint(&self) -> Result<SyncCheckpoint, StorageError>;
    fn set_sync_checkpoint(&self, checkpoint: &SyncCheckpoint) -> Result<(), StorageError>;
    
    /// Offline queue
    fn queue_operation(&self, op: CRDTOperation) -> Result<(), StorageError>;
    fn dequeue_operations(&self, limit: usize) -> Result<Vec<CRDTOperation>, StorageError>;
    fn clear_queued_operation(&self, op_id: &str) -> Result<(), StorageError>;
    
    /// Transaction support
    fn begin_transaction(&self) -> Result<Transaction, StorageError>;
}

pub struct Entity {
    pub id: EntityId,
    pub entity_type: String,
    pub value: Value,
    pub metadata: CRDTMetadata,
}

pub struct ApplyResult {
    pub applied: Vec<String>,      // Operation IDs applied
    pub conflicts: Vec<Conflict>,   // Conflicts requiring resolution
    pub new_checkpoint: SyncCheckpoint,
}
```

### 4.3 Platform Implementations

#### Mac Implementation (Swift)

```swift
// ProfileStorageAdapter.swift
import CoreData

/// Mac-specific implementation of the ProfileStorage trait
class CoreDataProfileStorage: ProfileStorage {
    private let container: NSPersistentContainer
    private let queue: DispatchQueue
    
    // MARK: - Profile Operations
    
    func loadProfile(id: UUID) throws -> Profile {
        let context = container.viewContext
        let request: NSFetchRequest<ProfileEntity> = ProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profile_id == %@", id as CVarArg)
        
        guard let entity = try context.fetch(request).first else {
            throw StorageError.profileNotFound
        }
        
        return try Profile(from: entity)
    }
    
    func saveProfile(_ profile: Profile) throws {
        let context = container.newBackgroundContext()
        
        try context.performAndWait {
            // Upsert pattern
            let request: NSFetchRequest<ProfileEntity> = ProfileEntity.fetchRequest()
            request.predicate = NSPredicate(format: "profile_id == %@", 
                                            profile.profileId as CVarArg)
            
            let entity: ProfileEntity
            if let existing = try context.fetch(request).first {
                entity = existing
            } else {
                entity = ProfileEntity(context: context)
                entity.profile_id = profile.profileId
            }
            
            // Update fields
            entity.updated_at = profile.updatedAt
            entity.version = Int32(profile.version)
            entity.preferences_data = try JSONEncoder().encode(profile.preferences)
            entity.vocabulary_data = try JSONEncoder().encode(profile.vocabulary)
            
            // CRDT metadata
            entity.crdt_hlc = profile.crdtMeta.hlc.toString()
            entity.vector_clock = try JSONEncoder().encode(profile.crdtMeta.vectorClock)
            
            try context.save()
        }
    }
    
    // MARK: - Sync Operations
    
    func getChangesSince(checkpoint: SyncCheckpoint) throws -> [CRDTOperation] {
        let context = container.viewContext
        
        // Query operations table for changes since checkpoint
        let request: NSFetchRequest<SyncOperationEntity> = SyncOperationEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "hlc_wall_time > %lld OR (hlc_wall_time == %lld AND hlc_logical > %d)",
            checkpoint.hlc.wallTime,
            checkpoint.hlc.wallTime,
            checkpoint.hlc.logical
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "hlc_wall_time", ascending: true),
            NSSortDescriptor(key: "hlc_logical", ascending: true)
        ]
        
        let operations = try context.fetch(request)
        return operations.map { $0.toCRDTOperation() }
    }
    
    func applyOperations(_ operations: [CRDTOperation]) throws -> ApplyResult {
        let context = container.newBackgroundContext()
        var result = ApplyResult()
        
        try context.performAndWait {
            for op in operations {
                do {
                    try applySingleOperation(op, in: context)
                    result.applied.append(op.op_id)
                } catch let error as ConflictError {
                    result.conflicts.append(error.conflict)
                }
            }
            
            // Update checkpoint to highest HLC seen
            if let lastOp = operations.last {
                result.newCheckpoint = SyncCheckpoint(hlc: lastOp.hlc)
            }
            
            try context.save()
        }
        
        return result
    }
    
    // MARK: - Offline Queue
    
    func queueOperation(_ op: CRDTOperation) throws {
        let context = container.newBackgroundContext()
        
        try context.performAndWait {
            let entity = QueuedOperationEntity(context: context)
            entity.op_id = op.op_id
            entity.op_type = op.op_type.rawValue
            entity.entity_type = op.entity_type
            entity.entity_id = op.entity_id
            entity.field_path = op.field_path
            entity.value_data = try JSONEncoder().encode(op.value)
            entity.hlc_wall_time = Int64(op.hlc.wall_time)
            entity.hlc_logical = Int32(op.hlc.logical)
            entity.peer_id = op.peer_id
            entity.created_at = Date()
            entity.retry_count = 0
            entity.status = "pending"
            
            try context.save()
        }
    }
    
    func dequeueOperations(limit: Int) throws -> [CRDTOperation] {
        let context = container.viewContext
        let request: NSFetchRequest<QueuedOperationEntity> = QueuedOperationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", "pending")
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        request.fetchLimit = limit
        
        let entities = try context.fetch(request)
        return entities.map { $0.toCRDTOperation() }
    }
}

// MARK: - Core Data Model Extension

// The Core Data model includes:
// - ProfileEntity
// - SyncOperationEntity (audit log)
// - QueuedOperationEntity (offline queue)
// - TombstoneEntity (soft deletes)
// - DeviceEntity (device records)
```

#### Android Implementation (Kotlin)

```kotlin
// ProfileStorageRoom.kt
@Dao
interface ProfileDao {
    @Query("SELECT * FROM profiles WHERE profile_id = :id")
    suspend fun getProfile(id: UUID): ProfileEntity?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProfile(profile: ProfileEntity)
    
    @Query("""
        SELECT * FROM sync_operations 
        WHERE (hlc_wall_time > :wallTime) 
        OR (hlc_wall_time = :wallTime AND hlc_logical > :logical)
        ORDER BY hlc_wall_time ASC, hlc_logical ASC
    """)
    suspend fun getChangesSince(wallTime: Long, logical: Int): List<SyncOperationEntity>
    
    @Insert
    suspend fun insertOperations(operations: List<SyncOperationEntity>)
    
    @Query("SELECT * FROM queued_operations WHERE status = 'pending' ORDER BY created_at LIMIT :limit")
    suspend fun getQueuedOperations(limit: Int): List<QueuedOperationEntity>
    
    @Query("UPDATE queued_operations SET status = 'sent' WHERE op_id = :opId")
    suspend fun markOperationSent(opId: String)
    
    @Query("UPDATE queued_operations SET retry_count = retry_count + 1 WHERE op_id = :opId")
    suspend fun incrementRetry(opId: String)
}

class RoomProfileStorage(private val db: WisprDatabase) : ProfileStorage {
    
    override suspend fun loadProfile(id: UUID): Profile {
        val entity = db.profileDao().getProfile(id)
            ?: throw StorageException.ProfileNotFound()
        return entity.toProfile()
    }
    
    override suspend fun saveProfile(profile: Profile) {
        val entity = ProfileEntity.fromProfile(profile)
        db.profileDao().upsertProfile(entity)
    }
    
    override suspend fun getChangesSince(checkpoint: SyncCheckpoint): Flow<CRDTOperation> {
        return db.profileDao()
            .getChangesSince(checkpoint.hlc.wallTime, checkpoint.hlc.logical)
            .map { it.toCRDTOperation() }
    }
    
    override suspend fun applyOperations(operations: List<CRDTOperation>): ApplyResult {
        return db.withTransaction {
            val result = ApplyResult()
            
            for (op in operations) {
                try {
                    applyOperation(op)
                    result.applied.add(op.opId)
                } catch (e: ConflictException) {
                    result.conflicts.add(e.conflict)
                }
            }
            
            // Update checkpoint
            operations.lastOrNull()?.let { lastOp ->
                result.newCheckpoint = SyncCheckpoint(hlc = lastOp.hlc)
            }
            
            result
        }
    }
    
    override suspend fun queueOperation(op: CRDTOperation) {
        val entity = QueuedOperationEntity.fromCRDTOperation(op)
        db.profileDao().insertQueuedOperation(entity)
    }
}
```

### 4.4 Current Mac Implementation (No Sync)

**For the current Mac app (no sync enabled):**

```swift
// LocalOnlyStorage.swift
/// Implementation that ignores sync operations.
/// Used when sync is disabled or in free tier.
class LocalOnlyStorage: ProfileStorage {
    private let coreDataStorage: CoreDataProfileStorage
    
    // Standard operations pass through to Core Data
    func loadProfile(id: UUID) throws -> Profile {
        return try coreDataStorage.loadProfile(id: id)
    }
    
    func saveProfile(_ profile: Profile) throws {
        // Save locally only, don't generate sync operations
        try coreDataStorage.saveProfile(profile)
    }
    
    // Sync operations - no-ops
    func getChangesSince(checkpoint: SyncCheckpoint) throws -> [CRDTOperation] {
        return [] // No sync = no changes to report
    }
    
    func applyOperations(_ operations: [CRDTOperation]) throws -> ApplyResult {
        // Ignore incoming operations
        return ApplyResult(applied: [], conflicts: [], newCheckpoint: SyncCheckpoint())
    }
    
    func queueOperation(_ op: CRDTOperation) throws {
        // No-op: Don't queue when sync disabled
    }
}
```

### 4.5 Storage Schema Evolution

**Version Strategy:**
- Profile schema version stored in root entity
- Migration handlers registered per version
- Downgrade not supported (sync from newer → older version blocked)
- Forward-compatible unknown fields ignored

```rust
// Schema migration
pub struct SchemaMigration {
    from_version: u32,
    to_version: u32,
    transform: Box<dyn Fn(Value) -> Value>,
}

pub struct SchemaManager {
    migrations: Vec<SchemaMigration>,
}

impl SchemaManager {
    pub fn migrate(&self, profile: &mut Profile) -> Result<(), MigrationError> {
        let current = profile.version;
        let target = CURRENT_SCHEMA_VERSION;
        
        for migration in self.migrations.iter() {
            if migration.from_version == current {
                profile.value = migration.transform(profile.value.clone());
                profile.version = migration.to_version;
            }
        }
        
        if profile.version != target {
            return Err(MigrationError::UnsupportedVersion);
        }
        
        Ok(())
    }
}
```

---

## 5. Security & Privacy

### 5.1 Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SECURITY LAYERS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  LAYER 1: Transport Security                             │   │
│   │  ├── TLS 1.3 for all connections                        │   │
│   │  ├── Certificate pinning (optional, enterprise)         │   │
│   │  └── OCSP stapling validation                           │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│   ┌──────────────────────────┴──────────────────────────────┐   │
│   │  LAYER 2: Authentication                                  │   │
│   │  ├── OAuth 2.0 / OIDC (Auth0/Firebase/Keycloak)         │   │
│   │  ├── JWT access tokens (short-lived: 1 hour)            │   │
│   │  ├── Refresh tokens (long-lived, rotatable)             │   │
│   │  └── Device attestation (future: device binding)        │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│   ┌──────────────────────────┴──────────────────────────────┐   │
│   │  LAYER 3: Payload Encryption                             │   │
│   │  ├── AES-256-GCM for profile data                       │   │
│   │  ├── Per-user encryption keys                           │   │
│   │  ├── HKDF key derivation from OAuth token               │   │
│   │  └── Key rotation on password change / logout           │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│   ┌──────────────────────────┴──────────────────────────────┐   │
│   │  LAYER 4: Local Storage Security                         │   │
│   │  ├── SQLCipher (SQLite with encryption)                 │   │
│   │  ├── Keychain (macOS) / Keystore (Android)              │   │
│   │  ├── Data Protection API on mobile                      │   │
│   │  ├── Auto-lock with screen lock                         │   │
│   │  └── Secure enclave for key material (if available)     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Encryption Design

#### Key Derivation

```rust
/// Key derivation using HKDF-SHA256
pub struct EncryptionKey {
    key_id: String,       // UUID identifying this key
    data_key: [u8; 32],   // AES-256 key for data encryption
    created_at: u64,      // Unix timestamp
    version: u32,         // Key format version
}

impl EncryptionKey {
    /// Derive encryption key from OAuth token + device secret
    pub fn derive(
        user_token: &str,
        device_secret: &[u8]
    ) -> Result<Self, KeyError> {
        // Step 1: HKDF extract
        let prk = Hkdf::<Sha256>::new(Some(device_secret), user_token.as_bytes());
        
        // Step 2: HKDF expand
        let mut okm = [0u8; 32];
        prk.expand(b"wispr-profile-encryption", &mut okm)
            .map_err(|_| KeyError::DerivationFailed)?;
        
        Ok(Self {
            key_id: Uuid::new_v4().to_string(),
            data_key: okm,
            created_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            version: 1,
        })
    }
    
    /// Encrypt profile data before transmission/storage
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<EncryptedPayload, CryptoError> {
        let nonce = generate_secure_random(12); // 96-bit for GCM
        
        let key = UnboundKey::new(&AES_256_GCM, &self.data_key)
            .map_err(|_| CryptoError::InvalidKey)?;
        let nonce = Nonce::try_assume_unique_for_key(&nonce)
            .map_err(|_| CryptoError::InvalidNonce)?;
        
        let mut ciphertext = plaintext.to_vec();
        let tag = seal_in_place_separate_tag(
            &key,
            nonce,
            Aad::empty(),
            &mut ciphertext,
            plaintext.len()
        ).map_err(|_| CryptoError::EncryptionFailed)?;
        
        Ok(EncryptedPayload {
            key_id: self.key_id.clone(),
            nonce: nonce.as_ref().to_vec(),
            ciphertext,
            tag: tag.as_ref().to_vec(),
            algorithm: "AES-256-GCM",
        })
    }
    
    pub fn decrypt(&self, payload: &EncryptedPayload) -> Result<Vec<u8>, CryptoError> {
        // Validate key_id matches
        if payload.key_id != self.key_id {
            return Err(CryptoError::KeyMismatch);
        }
        
        // ... decryption logic
    }
}
```

#### Encrypted Profile Storage

```typescript
// Encrypted at-rest representation
interface EncryptedProfile {
  profile_id: string;           // Unencrypted (needed for indexing)
  user_id: string;              // Unencrypted (access control)
  
  // Encryption metadata
  encryption: {
    algorithm: "AES-256-GCM";
    key_id: string;             // References key in Keychain/Keystore
    version: number;
  };
  
  // Encrypted payload (contains preferences, vocabulary, etc.)
  payload: {
    ciphertext: string;         // Base64
    nonce: string;              // Base64
    tag: string;                // GCM auth tag
    additional_data: string;    // AAD for integrity
  };
  
  // Sync metadata (unencrypted for server indexing)
  sync_meta: {
    hlc: HybridLogicalClock;
    device_id: string;
    timestamp: string;
  };
  
  // Integrity
  checksum: string;             // SHA-256 of decrypted payload
}
```

### 5.3 Authentication Flow

```
┌──────────┐                                         ┌──────────────┐
│ User     │                                         │ Wispr Cloud  │
└────┬─────┘                                         └──────┬───────┘
     │                                                      │
     │ 1. Sign In (OAuth - Google/Apple/GitHub)             │
     │─────────────────────────────────────────────────────▶│
     │                                                      │
     │ 2. OAuth Callback with code                          │
     │◀─────────────────────────────────────────────────────│
     │                                                      │
     │ 3. Exchange code for tokens                          │
     │─────────────────────────────────────────────────────▶│
     │                                                      │
     │ 4. Return JWT (access + refresh)                     │
     │◀─────────────────────────────────────────────────────│
     │                                                      │
┌────┴──────┐          5. Derive Encryption Key            │
│ Keychain  │◀────────────────── HKDF(user_secret, device)─┤
│ Store     │               device_secret                   │
└────┬──────┘                                             │
     │                                                      │
     │ 6. Initialize Local Profile (encrypted)              │
     │                                                      │
     │ 7. First Sync (or create new)                        │
     │─────────────────────(with access_token)─────────────▶│
     │                                                      │
     │ 8. Download encrypted snapshot                       │
     │◀─────────────────────────────────────────────────────│
     │                                                      │
┌────┴──────────┐                                           │
│ Decrypt with  │                                           │
│ derived key   │                                           │
└───────────────┘                                           │
```

### 5.4 Privacy Considerations

| Concern | Mitigation |
|---------|------------|
| **Voice data** | Never synced - remains local to device |
| **Transcription text** | Optional sync (user-controlled), encrypted |
| **Usage patterns** | Aggregated only, no individual tracking |
| **Third parties** | No analytics SDKs, self-hosted sync |
| **Data deletion** | GDPR-compliant deletion, 30-day backup retention |
| **Key escrow** | User manages own keys - we cannot decrypt |

### 5.5 Security Checklist

- [ ] TLS 1.3 for all API calls
- [ ] Certificate chain validation
- [ ] Access token expiration (1 hour)
- [ ] Refresh token rotation
- [ ] Device ID binding
- [ ] AES-256-GCM encryption
- [ ] Unique nonce per encryption
- [ ] SQLCipher for local DB
- [ ] Keychain/Keystore for keys
- [ ] Biometric auth for sensitive ops
- [ ] Memory scrubbing for keys
- [ ] Secure enclave when available
- [ ] Audit logging (sync events, not content)
- [ ] Rate limiting on sync endpoints
- [ ] Device revocation capability

---

## 6. API Contract

### 6.1 Base URLs

| Environment | URL |
|-------------|-----|
| Production | `https://api.speakr.dev/v1` |
| Staging | `https://api-staging.speakr.dev/v1` |
| Local | `http://localhost:8080/v1` |

### 6.2 Authentication

All endpoints require authentication via Bearer token:

```
Authorization: Bearer <jwt_access_token>
```

### 6.3 Endpoints

#### POST /sync/init - Initialize Sync Session

**Request:**
```json
{
  "device_id": "device-macbook-pro-001",
  "device_type": "mac",
  "device_name": "MacBook Pro (Work)",
  "capabilities": {
    "supports_offline": true,
    "max_payload_size": 10485760,
    "preferred_protocol": "delta"
  }
}
```

**Response (200):**
```json
{
  "session_id": "sess_abc123",
  "profile_id": "profile_xyz789",
  "sync_token": {
    "version": 1,
    "checkpoint": "cp_1234567890",
    "hlc": {
      "wall_time": 1712345678000,
      "logical": 0
    },
    "signature": "base64_hmac_signature"
  },
  "encryption_info": {
    "key_id": "key_abc123",
    "algorithm": "AES-256-GCM"
  },
  "server_config": {
    "max_operations_per_sync": 1000,
    "sync_interval_seconds": 300,
    "websocket_enabled": true
  }
}
```

**Response (404 - No existing profile):**
```json
{
  "status": "new_profile_required",
  "message": "No profile found for this user. Create new or restore from backup?"
}
```

#### POST /sync/delta - Submit and Receive Changes

**Request:**
```json
{
  "sync_token": { /* from init or last sync */ },
  "operations": [
    {
      "op_id": "op_001",
      "op_type": "update",
      "entity_type": "preferences",
      "entity_id": "prefs_main",
      "field_path": "theme",
      "value": "dark",
      "hlc": {
        "wall_time": 1712345678901,
        "logical": 0,
        "peer_id": "device-macbook-pro-001"
      }
    }
  ],
  "encrypted_payloads": {
    /* entity_id -> encrypted data */
    "vocab_001": "base64_encrypted_vocab_data"
  }
}
```

**Response (200 - Success):**
```json
{
  "sync_token": { /* updated checkpoint */ },
  "operations": [
    /* Operations from other devices since last sync */
  ],
  "encrypted_payloads": {
    /* Decrypt with local key */
  },
  "conflicts": [],
  "status": "success"
}
```

**Response (200 - Conflicts):**
```json
{
  "sync_token": { /* same as sent */ },
  "operations": [],
  "conflicts": [
    {
      "conflict_id": "conflict_001",
      "entity_type": "preferences",
      "entity_id": "prefs_main",
      "field_path": "theme",
      "local_value": "dark",
      "remote_value": "light",
      "local_hlc": { /* ... */ },
      "remote_hlc": { /* ... */ },
      "resolution_strategy": "last-write-wins",
      "resolved_value": "light",
      "winner": "remote"
    }
  ],
  "status": "conflict"
}
```

**Response (409 - Checkpoint Mismatch):**
```json
{
  "error": "checkpoint_mismatch",
  "message": "Client checkpoint is behind server. Perform full sync.",
  "server_checkpoint": "cp_9999999999"
}
```

#### POST /sync/full - Request Full Profile Snapshot

**Request:**
```json
{
  "device_id": "device-macbook-pro-001",
  "reason": "new_device"  // or "recovery", "reset"
}
```

**Response:**
```json
{
  "profile_snapshot": {
    "profile_id": "profile_xyz789",
    "encrypted_data": "base64_full_encrypted_profile",
    "checksum": "sha256_hash_of_decrypted",
    "size_bytes": 5242880
  },
  "sync_token": { /* fresh token */ },
  "server_time": "2026-04-07T20:00:00Z"
}
```

#### GET /sync/status - Check Sync Health

**Response:**
```json
{
  "profile_id": "profile_xyz789",
  "last_sync": "2026-04-07T19:45:00Z",
  "pending_operations": 0,
  "devices": [
    {
      "device_id": "device-macbook-pro-001",
      "device_type": "mac",
      "last_seen": "2026-04-07T19:45:00Z",
      "is_active": true
    },
    {
      "device_id": "device-pixel7-001",
      "device_type": "android",
      "last_seen": "2026-04-06T08:30:00Z",
      "is_active": false
    }
  ],
  "quota": {
    "storage_used_bytes": 10485760,
    "storage_limit_bytes": 10737418240,
    "syncs_today": 45
  }
}
```

#### DELETE /sync/device/:device_id - Revoke Device

Removes a device from the sync group. Other devices stop syncing with it.

**Response (204):** No content

**Response (403):** Cannot revoke primary without setting new primary

#### POST /sync/resolve-conflict - Manual Conflict Resolution

**Request:**
```json
{
  "conflict_id": "conflict_001",
  "resolution": "use_local"  // or "use_remote", "merge"
}
```

**Response:**
```json
{
  "resolved": true,
  "applied_operation": { /* operation reflecting resolution */ }
}
```

### 6.4 WebSocket /sync/realtime

**Connection:**
```javascript
const ws = new WebSocket(
  'wss://api.speakr.dev/v1/sync/realtime',
  [],
  { headers: { 'Authorization': 'Bearer ' + token } }
);
```

**Message Protocol:**

| Direction | Type | Description |
|-----------|------|-------------|
| C→S | `auth` | Send sync_token post-connection |
| S→C | `ready` | Server acknowledges, ready for ops |
| C→S | `operation` | Send operation to server |
| S→C | `operation` | Receive operation from other device |
| C→S | `ping` | Keepalive (every 30s) |
| S→C | `pong` | Keepalive response |
| S→C | `refresh` | Request full sync (checkpoint drift) |
| C→S | `ack` | Acknowledge operation receipt |
| S→C | `conflict` | Conflict detected, resolve required |

**Example Flow:**
```javascript
// Connection
ws.send(JSON.stringify({
  type: 'auth',
  sync_token: currentSyncToken
}));

// Server responds
// { type: 'ready', server_time: '...' }

// User changes setting locally
ws.send(JSON.stringify({
  type: 'operation',
  op: {
    op_id: 'op_002',
    op_type: 'update',
    entity_type: 'preferences',
    field_path: 'hotkey.key',
    value: 'space',
    hlc: generateHLC()
  }
}));

// Server acknowledges
// { type: 'ack', op_id: 'op_002' }

// Receive operation from phone
// { type: 'operation', ops: [{ ... }] }
ws.send(JSON.stringify({
  type: 'ack',
  op_id: 'received_op_id'
}));
```

### 6.5 Error Codes

| Code | HTTP | Description | Recovery |
|------|------|-------------|----------|
| `auth_required` | 401 | Missing or invalid token | Re-authenticate |
| `token_expired` | 401 | Token expired | Use refresh token |
| `forbidden` | 403 | Insufficient permissions | Check account tier |
| `not_found` | 404 | Profile not found | Create new profile |
| `checkpoint_mismatch` | 409 | Sync conflict | Perform full sync |
| `payload_too_large` | 413 | Exceeds size limit | Chunk data |
| `rate_limited` | 429 | Too many requests | Backoff and retry |
| `encryption_error` | 400 | Cannot decrypt payload | Check key derivation |
| `conflict` | 200 | Conflicts detected (body) | Resolve manually or accept server |
| `service_unavailable` | 503 | Server maintenance | Retry after delay |

### 6.6 Rate Limits

| Resource | Default Limit | Notes |
|----------|---------------|-------|
| Auth requests | 10/min | Login attempts |
| Sync requests | 60/min | Delta sync calls |
| Full syncs | 5/day | Expensive operation |
| WebSocket connections | 5/device | Concurrent connections |
| Payload size | 10MB/request | Max request size |
| Profile storage | 10GB/user | Encrypted data |

---

## 7. Implementation Roadmap

### 7.1 Phase 1: Preparation (Current)

**Goal:** Enable future sync without changing current implementation

**Tasks:**
- [ ] Define storage abstraction interface in current code
- [ ] Implement `LocalOnlyStorage` (no-op sync methods)
- [ ] Add CRDT metadata fields to data models (ignored locally)
- [ ] Design profile schema in current persistence layer
- [ ] Document sync enablement path

**Deliverables:**
- Storage abstraction protocol/interface
- Local-only implementation
- Schema with sync metadata (dormant)

### 7.2 Phase 2: Sync Foundation

**Goal:** Basic sync functionality on Mac

**Tasks:**
- [ ] Build Rust sync engine with CRDT support
- [ ] Implement secure key derivation
- [ ] Create sync service backend
- [ ] Add OAuth integration to Mac app
- [ ] Implement encrypted storage adapter
- [ ] Add sync preference UI

**Deliverables:**
- Working sync on single device (Mac)
- Cloud infrastructure
- Auth system

### 7.3 Phase 3: Multi-Device

**Goal:** Sync between multiple Macs

**Tasks:**
- [ ] Multi-device session management
- [ ] Conflict resolution UI
- [ ] Offline queue implementation
- [ ] Real-time sync (WebSocket)
- [ ] Device management UI (revoke devices)

**Deliverables:**
- Multi-Mac sync
- Conflict resolution

### 7.4 Phase 4: Android

**Goal:** Android app with sync

**Tasks:**
- [ ] Port whisper.cpp to Android (JNI/Rust FFI)
- [ ] Android UI implementation
- [ ] Android storage adapter (Room/SQLCipher)
- [ ] Cross-platform sync testing
- [ ] Shared Rust sync engine

**Deliverables:**
- Android app with sync
- Cross-platform compatibility verified

### 7.5 Current Implementation Guidance

**For the current Mac app (Phase 0):**

1. **Model Classes:** Add `crdt_meta` field to entities, but ignore it locally
2. **Storage Layer:** Design for pluggable implementation
3. **Data Format:** Use JSON-serializable structures that match sync schema
4. **IDs:** Use UUIDs for all entities (not sequential integers)

**Example Current Code Pattern:**

```swift
// Current implementation - ready for future sync
struct Preferences: Codable {
    let theme: String
    let fontSize: String
    let hotkey: HotkeyConfig
    
    // Add this now, unused locally
    var crdtMeta: CRDTMetadata?
    
    // Local-only initialization
    init(theme: String, fontSize: String, hotkey: HotkeyConfig) {
        self.theme = theme
        self.fontSize = fontSize
        self.hotkey = hotkey
        self.crdtMeta = nil // Ignored for local-only
    }
}

// Storage protocol - current implementation
protocol PreferencesStore {
    func load() -> Preferences
    func save(_ preferences: Preferences)
    // Future methods (no-op for now):
    // func getChangesSince(_ checkpoint: SyncCheckpoint) -> [CRDTOperation]
}
```

This approach means:
- Current app works without sync
- No breaking changes when adding sync
- Sync layer is additive, not replacing

---

## Appendix A: CRDT Deep Dive

### A.1 Why CRDTs?

Conflict-Free Replicated Data Types provide:
- **Strong eventual consistency:** All devices converge to same state
- **Offline capability:** Operations queued locally, merged later
- **No coordination:** Devices can sync independently
- **Deterministic:** Same operations produce same result everywhere

### A.2 State-based vs Operation-based

| Approach | Pros | Cons |
|----------|------|------|
| **State-based** (ours) | Simple, batch operations | More bandwidth (full state) |
| **Operation-based** | Efficient, low bandwidth | Requires causality tracking |

**Hybrid approach:** Delta-operations with periodic state snapshots

### A.3 Example: Set CRDT

```rust
// Grow-Only Set (G-Set)
pub struct GSet<T: Ord + Clone> {
    elements: BTreeSet<T>,
}

impl<T: Ord + Clone> GSet<T> {
    pub fn add(&mut self, element: T, hlc: HybridLogicalClock) {
        self.elements.insert(element);
    }
    
    pub fn merge(&mut self, other: &GSet<T>) {
        self.elements.extend(other.elements.iter().cloned());
    }
}

// Usage: Custom vocabulary words
// Mac adds "Speakr" → { "Speakr" }
// Android adds "whisper.cpp" → { "whisper.cpp" }
// Sync: Merge produces → { "Speakr", "whisper.cpp" }
// No conflict: Union of both sets
```

### A.4 Example: Register CRDT

```rust
// Last-Write-Wins Register (LWW)
pub struct LWWRegister<T: Clone> {
    value: T,
    timestamp: HybridLogicalClock,
}

impl<T: Clone> LWWRegister<T> {
    pub fn set(&mut self, value: T, hlc: HybridLogicalClock) {
        if hlc > self.timestamp {
            self.value = value;
            self.timestamp = hlc;
        }
    }
    
    pub fn merge(&mut self, other: &LWWRegister<T>) {
        if other.timestamp > self.timestamp {
            self.value = other.value.clone();
            self.timestamp = other.timestamp.clone();
        }
    }
}

// Usage: Theme preference
// Mac sets "dark" at T=10 → theme="dark"
// Android sets "light" at T=5 → no change (T=10 wins)
// Conflict resolved: "dark" preserved
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **CRDT** | Conflict-Free Replicated Data Type - data structure that merges changes without conflicts |
| **HLC** | Hybrid Logical Clock - timestamp that combines physical and logical time |
| **Vector Clock** | Data structure tracking event ordering across distributed nodes |
| **Delta Sync** | Synchronization of only changed data, not full state |
| **Tombstone** | Marker indicating an entity was deleted (needed for CRDT deletes) |
| **Offline Queue** | Local buffer for operations pending network availability |
| **LWW** | Last-Write-Wins - conflict resolution strategy |

---

## Appendix C: References

1. [CRDTs: An Overview](https://arxiv.org/abs/1806.10254) - Shapiro et al.
2. [Hybrid Logical Clocks](https://cse.buffalo.edu/tech-reports/2014-04.pdf) - Kulkarni et al.
3. [Automerge](https://github.com/automerge/automerge) - CRDT implementation reference
4. [Yjs](https://github.com/yjs/yjs) - CRDTs for JavaScript
5. [Ditto](https://ditto.live/) - Commercial sync platform (inspiration)

---

**Document Status:** Design Complete  
**Next Review:** Before Phase 2 Implementation

This document provides the foundation for cross-device sync. The current Mac implementation should follow the Phase 1 guidance to ensure seamless future extensibility.

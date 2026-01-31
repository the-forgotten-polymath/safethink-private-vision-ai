# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SafeThink is a privacy-first iOS AI assistant that runs Qwen 3.5 LLMs entirely on-device via MLX Swift. No user data leaves the device. Network access is only used for model downloads from HuggingFace and optional user-triggered web search (DuckDuckGo).

The full product specification is in `docs/SPEC.md` — treat it as the single source of truth for features.

## Build System

This project uses **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# Regenerate .xcodeproj after changing project.yml
xcodegen generate

# Build (requires Xcode 16+, iOS 17+ deployment target)
xcodebuild -project SafeThink.xcodeproj -scheme SafeThink -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project SafeThink.xcodeproj -scheme SafeThinkTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

There is also a `SafeThink/Package.swift` for SPM resolution, but the primary build is via the XcodeGen-generated xcodeproj. After modifying `project.yml`, always run `xcodegen generate`.

## Architecture

**Pattern:** MVVM + Service Layer (all SwiftUI)

```
SafeThinkApp.swift (entry point)
  → OnboardingView / LockScreenView / ContentView (4-tab TabBar)

ContentView tabs: Chat | Models | Privacy | Settings
```

### Data Flow
- **Views** bind to `@StateObject` ViewModels
- **ViewModels** call into singleton **Services** (`ServiceName.shared`)
- **Services** own business logic and persist via `DatabaseService` (GRDB/SQLite)
- **InferenceService** wraps MLX Swift for LLM generation (AsyncStream-based streaming)
- **EmbeddingService** wraps `swift-embeddings` (Bert.ModelBundle, requires iOS 18+ for MLTensor)

### Key Services

| Service | Role | Key Dependencies |
|---------|------|-----------------|
| InferenceService | LLM loading, streaming token generation, thermal monitoring | MLX, MLXLLM, MLXLMCommon |
| EmbeddingService | all-MiniLM-L6-v2 text embeddings (384D), cosine similarity | Embeddings (swift-embeddings), CoreML |
| DatabaseService | SQLite via GRDB with FTS5 full-text search, embedding BLOB storage | GRDB |
| ModelDownloadService | HuggingFace model download via LLMModelFactory, progress tracking | MLXLLM, MLXLMCommon |
| SecurityService | FaceID/TouchID, PIN (PBKDF2+Keychain), lockout logic | LocalAuthentication, CommonCrypto |
| DocumentService | PDF/TXT/DOCX/CSV extraction, chunking, RAG pipeline | PDFKit |
| MemoryService | Persistent user memory with embedding-based retrieval | EmbeddingService, DatabaseService |

### Model Loading

Models are loaded via `ModelConfiguration(id: huggingFaceId)` passed to `LLMModelFactory.shared.loadContainer()`. Do **not** use `ModelConfiguration.id()` — `id` is an instance property of type `ModelConfiguration.Identifier`, not a static factory.

The model registry is in `ModelInfo.registry` (static array in `SafeThink/Models/ModelInfo.swift`), with HuggingFace URLs like `https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit`.

### Database

GRDB with versioned migrations in `DatabaseService.migrate()`:
- **v1_initial**: conversations, messages, attachments, messages_fts (FTS5), memories, document_chunks, network_log
- **v2_embeddings**: adds `embeddingVector BLOB` columns to memories and document_chunks

Embedding vectors are stored as raw `[Float]` bytes via `DatabaseService.floatsToData()`/`dataToFloats()`.

### Embedding Service Availability

The `swift-embeddings` package (`Bert.ModelBundle`) requires **iOS 18.0+** because it uses `MLTensor` from CoreML. On iOS 17, the embedding service gracefully returns without loading. The app still works — it just falls back to non-semantic retrieval for memories and documents.

## SPM Dependencies

Defined in `project.yml` under `packages:`. Key products linked to the app target:
- **MLX**, **MLXLLM**, **MLXLMCommon** — on-device LLM inference
- **GRDB** — SQLite database
- **MarkdownUI** — markdown rendering in chat
- **Splash** — code syntax highlighting
- **Embeddings** (from swift-embeddings) — BERT sentence embeddings

## Privacy Constraints

This is a zero-data-collection app. When writing new features:
- Never make network requests without explicit user trigger
- Log all outbound requests via `NetworkLogService.shared.log()`
- All processing must happen on-device
- Model files must be excluded from iCloud backup (`isExcludedFromBackup = true`)

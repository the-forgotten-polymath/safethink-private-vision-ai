# AGENTS.md

Instructions for Codex working in `/Users/faizan/Documents/Personal/Projects/PrivateAI`.

## Purpose

- This repository is `SafeThink`, a privacy-first iOS AI assistant built with SwiftUI.
- Read [`CLAUDE.md`](/Users/faizan/Documents/Personal/Projects/PrivateAI/CLAUDE.md) and [`docs/SPEC.md`](/Users/faizan/Documents/Personal/Projects/PrivateAI/docs/SPEC.md) for product intent.
- Treat the current codebase as the implementation source of truth when the spec and code disagree. Call out important drift instead of silently “fixing” the app toward the spec.

## Project Layout

- App code lives under `SafeThink/`.
- Tests live under `SafeThinkTests/`.
- The app is SwiftUI with MVVM plus singleton services.
- Key folders:
- `SafeThink/App`: entry point and tab container
- `SafeThink/Models`: GRDB-backed data models and model registry
- `SafeThink/Services`: business logic, persistence, inference, download, security, export, search
- `SafeThink/ViewModels`: screen-facing orchestration
- `SafeThink/Views`: SwiftUI screens and components

## Build And Test

- The project uses XcodeGen. If you change build settings, dependencies, targets, or entitlements in `project.yml`, regenerate the project with `xcodegen generate`.
- Primary project file: [`project.yml`](/Users/faizan/Documents/Personal/Projects/PrivateAI/project.yml)
- Generated project: [`SafeThink.xcodeproj`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink.xcodeproj)
- Useful commands:

```bash
xcodegen generate
xcodebuild -project SafeThink.xcodeproj -scheme SafeThink -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project SafeThink.xcodeproj -scheme SafeThinkTests -destination 'platform=iOS Simulator,name=iPhone 16' test
xcodebuild -project SafeThink.xcodeproj -scheme SafeThinkTests -showdestinations
```

- Prefer validating with the smallest command that proves the change.
- When changing `project.yml`, do not hand-edit the `.xcodeproj` expecting it to persist.
- Do not assume `iPhone 16` exists locally just because it appears in older docs. Query available destinations first and use an installed simulator. In the current environment, `iPhone 17`-family simulators are available while `iPhone 16` is not.

## Architecture

- Entry point: [`SafeThinkApp.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/App/SafeThinkApp.swift)
- Main navigation: [`ContentView.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/App/ContentView.swift)
- Tabs: Chat, Models, Privacy, Settings
- Pattern:
- Views bind to `@StateObject` / `@ObservedObject` view models
- View models call singleton services like `InferenceService.shared`
- Services own business logic and persistence via `DatabaseService`

## Important Implementation Facts

- Database:
- Implemented with GRDB in [`DatabaseService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/DatabaseService.swift)
- Current schema uses SQLite tables plus FTS5
- Embeddings are stored as raw `BLOB` data via `floatsToData` / `dataToFloats`
- The current implementation does **not** use `sqlite-vec`
- The current implementation does **not** use SQLCipher

- Embeddings:
- [`EmbeddingService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/EmbeddingService.swift) depends on `swift-embeddings`
- Semantic embeddings only work on iOS 18+ because `Bert.ModelBundle` requires `MLTensor`
- On iOS 17 the app falls back to non-semantic behavior for memories and documents

- Model management:
- [`ModelInfo.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Models/ModelInfo.swift) is the local model registry
- Downloads use MLX / Hugging Face IDs in [`ModelDownloadService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/ModelDownloadService.swift)
- The app writes a local `.download_complete` marker under `Documents/models`, but actual model artifacts are loaded from MLX’s hub cache
- `ModelManagerViewModel.activateModel` loads by Hugging Face repo ID, not by the local marker directory

- Inference:
- [`InferenceService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/InferenceService.swift) streams text with `AsyncStream`
- Generation and model loading are `@MainActor` service methods
- There is thermal cancellation logic and a background unload helper, but verify call sites before assuming it is fully wired into app lifecycle

- Documents and memory:
- [`DocumentService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/DocumentService.swift) uses character-count chunking, not token-aware chunking
- DOCX extraction is currently a simplified text-strip approach, not a full parser
- Retrieval falls back to recent/first chunks when embeddings are unavailable
- [`MemoryService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/MemoryService.swift) uses simple heuristic extraction for candidate memories

## Privacy And Network Rules

- SafeThink is privacy-first. Do not add network access casually.
- Any outbound request must be user-triggered.
- Log outbound requests through [`NetworkLogService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/NetworkLogService.swift).
- Existing networked areas are model download and explicit web search in [`SearchService.swift`](/Users/faizan/Documents/Personal/Projects/PrivateAI/SafeThink/Services/SearchService.swift).
- Preserve local-only behavior for chats, memories, documents, and media processing.

## Editing Guidance

- Prefer focused bug fixes over broad refactors.
- Keep MVVM boundaries intact unless a change clearly improves correctness.
- Reuse existing singletons and persistence helpers instead of introducing parallel abstractions.
- If you change persistence schema or model fields, review migrations, GRDB record conformance, and affected tests together.
- If you change app permissions, entitlements, or package dependencies, update `project.yml` and regenerate the project.
- If you fix behavior that the spec describes differently from the code, mention whether you aligned to the spec or preserved current implementation.

## Testing Guidance

- For persistence changes, run the relevant `SafeThinkTests` first.
- For UI-adjacent logic, at minimum compile the app target.
- For model, embedding, or Apple-framework-heavy code, prefer compile/build verification if simulator tests are brittle.
- When tests fail because the repo already has unrelated breakage, separate your change from pre-existing failures in the report.

## Current Drift To Keep In Mind

- The spec and `CLAUDE.md` mention Qwen 3.5 models, `sqlite-vec`, and SQLCipher; current code uses Qwen 3 registry entries, GRDB + FTS5, and raw embedding blobs.
- `CLAUDE.md` build examples currently reference `iPhone 16`, but this machine’s installed simulators do not include it.
- The spec describes richer security and document processing than the current implementation provides.
- When fixing bugs, avoid assuming the aspirational spec is already implemented.

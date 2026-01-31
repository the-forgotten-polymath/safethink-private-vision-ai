# SafeThink - Product Specification

> "The AI assistant that never sends your data anywhere"

## 1. Product Overview

- **Name:** SafeThink
- **Platform:** iOS (initial), Android (future)
- **Price:** Free
- **Distribution:** Apple App Store
- All model inference occurs locally using Qwen 3.5 small models
- ChatGPT-like experience without cloud dependency
- Network access ONLY for: model downloads, optional user-triggered web search

## 2. Supported Devices

| Tier | Devices | RAM | Max Model | Performance |
|---|---|---|---|---|
| Minimum | iPhone 15 (A16+), iOS 17+ | 6GB | Qwen3.5-0.8B | ~30 tok/s |
| Recommended | iPhone 15 Pro, 16 | 8GB | Qwen3.5-2B | ~25 tok/s |
| Premium | iPhone 16 Pro/Max | 8GB | Qwen3.5-4B | ~15 tok/s |
| iPad | iPad Pro M1+ | 8-16GB | Qwen3.5-9B | ~20 tok/s |

Storage: 3-6 GB free minimum.

## 3. Model Support

Models downloaded on demand (not bundled). Format: MLX (converted from HuggingFace).

| Model | Size (4-bit) | Recommended For |
|---|---|---|
| Qwen3.5-0.8B | ~0.7GB | All supported iPhones |
| Qwen3.5-2B | ~1.5GB | iPhone 15+ |
| Qwen3.5-4B | ~2.8GB | iPhone 15 Pro+ |
| Qwen3.5-9B | ~5.5GB | iPad Pro M1+ only |

## 4. Architecture

**Pattern:** MVVM with service layer

```
UI Layer (SwiftUI)
  -> ViewModels
    -> Application Services
      -> MLX Swift inference engine + all-MiniLM-L6-v2 embeddings
        -> Qwen model + sqlite-vec
          -> Apple Silicon (CPU, GPU, ANE)
```

## 5. Technology Stack

| Component | Technology |
|---|---|
| UI | SwiftUI |
| Architecture | MVVM + Services |
| LLM Inference | MLX Swift |
| Embedding Model | all-MiniLM-L6-v2 via swift-embeddings / MLX |
| Vector Search | sqlite-vec extension |
| Database | GRDB.swift (SQLite + FTS5 + sqlite-vec) |
| Image Processing | Core Image + Vision Framework |
| Speech-to-Text | SFSpeechRecognizer (on-device) |
| Biometrics | LocalAuthentication |
| Secure Storage | iOS Keychain |
| PDF Processing | PDFKit |
| Markdown | swift-markdown-ui |
| Code Highlighting | Splash |

## 6. Core Services (12 total)

1. **InferenceService** - Model loading, token generation, streaming, prompt formatting, multimodal image encoding, memory management
2. **EmbeddingService** - all-MiniLM-L6-v2 loading, text-to-384D-vector encoding, batch embedding for document chunks
3. **DatabaseService** - Schema (conversations, messages, attachments, memories, embeddings), CRUD, FTS5 search, sqlite-vec vector search
4. **ModelDownloadService** - HuggingFace downloads, SHA256 verification, progress tracking, model version management
5. **SecurityService** - FaceID/TouchID auth, PIN protection, encrypted storage
6. **VoiceService** - On-device speech recognition (hold-to-talk, auto-stop, manual stop)
7. **DocumentService** - PDF/TXT/DOCX/CSV text extraction, chunking, embedding generation, vector storage, document retrieval (RAG)
8. **ImageService** - Core Image filters (crop, blur, annotate, background removal), AI-assisted suggestions
9. **SearchService** - DuckDuckGo API (explicit user trigger only)
10. **MemoryService** - Persistent memory extraction, storage, embedding-based retrieval, system prompt injection
11. **ExportService** - JSON/Markdown/TXT/PDF chat export
12. **NetworkLogService** - Privacy audit log of all outbound requests

## 7. Core Features (13 total)

### Feature 1: Chat Interface
- Streaming token responses with blinking cursor
- Markdown rendering (bold, italic, lists, headers, blockquotes, tables, links)
- Syntax-highlighted code blocks with copy button (SF Mono)
- Regenerate response, edit user prompt, stop generation, copy messages
- Context window indicator ("2.1K / 8K tokens")
- Context trimming: summarize older messages, keep recent, drop earliest if needed
- KV cache reuse during generation for speed
- Token/sec display during generation

### Feature 2: Conversation Management
- Rename, delete, archive, pin conversations
- Search chat history (SQLite FTS5)
- Auto-generated titles from first message
- Sections: Pinned, Today, Yesterday, This Week, Older

### Feature 3: Model Manager
- Download models from HuggingFace with progress bar
- Resumable background downloads via URLSession
- SHA256 checksum verification post-download
- Delete models (swipe or button, confirmation dialog)
- Switch active model (unload current -> load new, warn about context loss)
- Storage display: total models size, device free space
- Version checking via remote JSON registry (fetched max once/day)
- "Update Available" badge when newer model exists
- Device compatibility indicator per model (green/yellow/red)

### Feature 4: Web Search (Privacy-First)
- NEVER triggered automatically
- User must explicitly: tap "Search Web" button, use `/search` command, or accept suggestion
- DuckDuckGo Instant Answer API (no API key, no tracking)
- Visual globe icon + "Web-enhanced" badge on responses
- Source URLs displayed as tappable links
- All search results processed locally by on-device model
- Every request logged in Privacy Dashboard

### Feature 5: Document Intelligence (Local RAG)
- Supported formats: PDF (PDFKit), TXT, DOCX (ZIP+XML), CSV
- Local RAG pipeline:
  1. Document uploaded -> text extracted
  2. Text chunked (~2000 tokens, 200 overlap)
  3. Chunks embedded via all-MiniLM-L6-v2 (384D vectors)
  4. Vectors stored in sqlite-vec
  5. User question -> embedded -> vector similarity search
  6. Top relevant chunks injected into prompt context
  7. LLM generates grounded response
- For large docs: map-reduce summarization or user selects page range
- Auto-detect doc type and suggest actions: Summarize, Extract Key Points, Q&A
- Character/token count display

### Feature 6: Image Analysis (Multimodal Vision)
- Input: camera, photo library, drag-and-drop (iPad), clipboard, file import
- Qwen3.5 native multimodal: describe, OCR, visual Q&A, code from screenshots, document scanning
- Image preprocessed (resize to <=1280x1280, RGB)
- Vision tokens via multimodal processor alongside main model
- Limit: 2-3 images per turn (memory constraints)
- Progress: "Analyzing image..." spinner

### Feature 7: Image Editing Tools
- AI analyzes and SUGGESTS edits; native frameworks EXECUTE them
- Tools: Core Image filters (sepia, B&W, vivid), brightness/contrast, crop, rotate, annotate (PencilKit), text overlay, blur regions, background removal (Vision VNGeneratePersonSegmentationRequest), auto-enhance
- AI-assisted flow: user asks "how to improve?" -> AI suggests -> tappable action chips apply edits
- Export: save to Photos, share sheet, clipboard, Files app (PNG/JPEG)

### Feature 8: Voice Input
- SFSpeechRecognizer with `requiresOnDeviceRecognition = true`
- Modes: hold-to-talk, toggle, auto-stop (2s silence, configurable)
- Real-time transcription in input field as user speaks
- Waveform animation during recording
- No audio sent to any server

### Feature 9: Persistent Memory System
- Local memory that learns about user over time
- Stored: user preferences, writing style, languages, personal notes, knowledge snippets, conversation summaries
- Memory DB schema: memory_id, memory_type, memory_text, embedding_vector (384D), created_at, relevance_score
- Workflow:
  1. Conversation occurs
  2. System extracts candidate memory items (via LLM)
  3. User optionally confirms saving
  4. Memory embedded and stored in sqlite-vec
  5. Future conversations: relevant memories retrieved via embedding similarity and injected into system prompt

### Feature 10: Prompt Templates
- Built-in: summarize text, explain code, fix grammar, translate, generate email, rewrite content
- User-created custom templates
- Quick-access via templates button in input bar

### Feature 11: Security
- FaceID/TouchID via LocalAuthentication (prompt on launch + return from background)
- 4-6 digit PIN fallback (PBKDF2 hash with salt in Keychain, 100K iterations)
- 5 failed PINs -> escalating lockout (30s, 1min, 5min)
- Lock timeout: immediate / 30s / 1min / 5min / never
- SQLite encrypted via SQLCipher (key in Keychain)
- All user files under NSFileProtectionComplete
- Optional self-destruct after N failed attempts (wipes chats, not models)

### Feature 12: Settings
- **General:** Theme (system/light/dark), haptic feedback, app icon alternatives
- **AI Model:** Active model picker, context window limit (2K-32K), temperature (0-2), top-P (0-1), system prompt editor, response format (normal/concise/detailed), tok/sec toggle
- **Voice:** Input mode, auto-stop duration, recognition language
- **Security:** Biometric toggle, PIN set/change/remove, lock timeout, self-destruct
- **Data & Privacy:** Export all/single chats (JSON/MD/TXT/PDF), clear chat history, clear documents, clear memories
- **Storage:** Breakdown (models, chats, documents, embeddings, cache), cache clear, link to Model Manager
- **About:** Version, licenses, bundled privacy policy

### Feature 13: Privacy Dashboard
- Hero stat: "X conversations, Y messages -- all stored locally"
- Network activity log: timestamp, destination, purpose, data size for every outbound request
- "No data has left your device" when log is empty
- Permissions grid: camera, microphone, speech, photos, FaceID, network
- Data controls: "Delete All My Data" and "Delete Everything Including Models" (require auth + typed "DELETE" confirmation)

## 8. Data Architecture

### Storage Layout
```
SafeThink/
  models/          -> MLX model files
  database/        -> chat.sqlite (encrypted, FTS5, sqlite-vec)
  documents/       -> uploaded files
  embeddings/      -> embedding model files (all-MiniLM-L6-v2)
  exports/         -> user-exported files
```

### Database Schema
- `conversations` (id, title, created_at, updated_at, model_id, is_pinned, is_archived, message_count)
- `messages` (id, conversation_id, role, content, created_at, token_count, generation_time, tokens_per_sec, has_attachments)
- `attachments` (id, message_id, type, file_path, file_name, file_size, mime_type, metadata JSON)
- `messages_fts` USING fts5 (content) -- full-text search
- `memories` (memory_id, memory_type, memory_text, embedding_vector, created_at, relevance_score)
- `document_chunks` (id, document_id, chunk_text, embedding_vector, chunk_index)
- `network_log` (id, timestamp, destination, purpose, data_size)

### Data Protection
- Chat DB: NSFileProtectionComplete + SQLCipher AES-256
- User files: NSFileProtectionComplete
- Model files: NSFileProtectionCompleteUntilFirstUserAuthentication
- PIN hash + encryption key: Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
- No iCloud for models (excluded via isExcludedFromBackup)
- No analytics SDKs, no crash reporting SDKs, no tracking

## 9. UI Screens

**Navigation (iPhone):** TabBar with 4 tabs: Chat, Model Manager, Privacy Dashboard, Settings

1. **Onboarding** - Welcome + privacy promise, model selection, download with progress, optional security setup
2. **Chat Screen** - Conversation thread, input bar (text field + attachment + mic + send), stop button during generation
3. **Conversation List** - Search bar (FTS), segmented (All/Pinned/Archived), swipe actions (pin/archive/delete)
4. **Model Manager** - Storage header, model cards (name, params, quant, size, status, compatibility badge), download progress
5. **Settings** - Grouped list (iOS style), all settings from Feature 12
6. **Privacy Dashboard** - All elements from Feature 13
7. **Image Editor** - Filter picker, live preview, AI suggestion chips, export options

## 10. Performance Targets

| Metric | Target |
|---|---|
| App launch | < 2 seconds |
| Model load | < 3 seconds |
| First token | < 1 second |
| Token generation | 15-40 tok/s (device dependent) |

### Optimizations
- Metal GPU offloading (all layers)
- Memory-mapped model loading (mmap)
- KV cache reuse + pre-allocation
- Batch prompt processing (512 tokens)
- Streaming via AsyncStream on background queue, UI via @MainActor
- Background: keep model loaded 30s, then unload; reload on foreground return
- Thermal monitoring: reduce threads on `.serious`/`.critical`
- Low Power Mode: reduce threads to 2, suggest smaller model

### Memory Budget (Qwen3.5-2B + embeddings on 8GB iPhone)
- LLM loaded: ~1.6GB
- KV cache (8K ctx): ~0.5GB
- Embedding model: ~50MB
- App + overhead: ~0.3GB
- **Total: ~2.5GB** -- well within limits

## 11. App Store Compliance

SafeThink intentionally avoids:
- Dynamic scripting engines
- Shell access / arbitrary code execution
- Plugin execution systems / heavy agent frameworks
- On-device fine-tuning
- Hidden plugin systems
- Remote AI inference services

Privacy nutrition label: **"Data Not Collected"** for all categories.

## 12. Android Port Notes

| Component | iOS | Android |
|---|---|---|
| Inference | MLX Swift | llama.cpp via JNI/NDK |
| Embeddings | swift-embeddings / MLX | ONNX Runtime / llama.cpp |
| UI | SwiftUI | Jetpack Compose |
| Database | GRDB.swift (SQLite) | Room (SQLite) -- same schema |
| Speech | SFSpeechRecognizer | Android SpeechRecognizer (offline) |
| Biometrics | LocalAuthentication | BiometricPrompt API |
| Image Processing | Core Image + Vision | GPUImage / ML Kit |
| Vector Search | sqlite-vec | sqlite-vec (same) |

**Shared across platforms:** model registry JSON format, database schema, chat export format, system prompts, prompt templates, DuckDuckGo integration.

## 13. MVP Scope (v1)

**Included:** local LLM chat, chat history + search, model manager, voice input, multimodal image analysis, document processing with RAG, persistent memory system, prompt templates, security lock, chat export, privacy dashboard, image editing tools, web search

**Excluded:** agent frameworks, plugin marketplace, on-device training, multi-model parallel conversations

## 14. Future Roadmap

- **v2:** Improved document search, advanced embeddings, local knowledge bases
- **v3:** Multi-model switching, Apple Neural Engine optimization
- **v4:** Android version, optional encrypted cross-device sync

# AI Editor — implementation plan for approval

Status: Approved by the user; implementation and validation recorded in AI-Editor-Validation.md.
Branch: `feat/ai-editor`
Isolated checkout: `/Users/robertrhea/Documents/Codex/Author-AI-Editor`
Base: `feat/authoring-app-ui` at `16bf701`.

## Decision requested

Approve the scope, architecture, and staged delivery below. Approval authorizes implementation and testing on the feature branch. Merging into the application branch remains a separate review step.

## Outcome

Provide an editorial review panel for scenes, chapters, and entire novels, with configurable personas, explicit model selection, and durable review history. For OpenAI, populate the model picker from the authenticated account's `/v1/models` response, showing GPT-family models and retaining manual entry for a model not returned by that endpoint. Keep fallback choices while the catalog loads; surface account, network, and API errors rather than silently changing the selected model. Reviews identify issues, explain their effect, cite manuscript evidence, and recommend actions. They do not rewrite passages or change manuscript content.

Apple Intelligence on-device is the default when no other model is selected. Implement Apple first. Other models are explicit user choices; never silently upload content to a different provider.

## Repository baseline and prerequisite

The application is SwiftUI with an AuthorData Core Data layer, AuthorUI workspace, and native app entry point. The active schema is V4. Documents form a hierarchy; there are no separate Novel, Chapter, or Scene entities.

The original checkout has uncommitted AIProviderSettings.swift, AppPreferencesView.swift, ProjectPreferencesView.swift, and changes to workspace, app, package, project configuration, documentation, and tests. These were inspected but are not part of the isolated branch's committed base. Leave them untouched. Before implementation, integrate their finalized commit(s) into this branch, or coordinate an explicit snapshot if they remain uncommitted. Do not overwrite or implicitly commit unrelated work. Recheck the baseline and exact schema version before making implementation changes.

## Product behavior

### Personas

Ship Technical / Copy, Story / Developmental, Character & Continuity, Line & Style, Academic, and Genre & Reader Experience presets. Each preset must have a distinct professional remit: copy editors apply grammar and house-style conventions; developmental editors address manuscript architecture; continuity editors track the established record; line editors assess the reading experience at paragraph and sentence level; academic editors assess argument and evidence as presented; and acquiring editors assess genre promise and target-reader experience without making market guarantees. Seed exactly one versioned built-in persona per preset key, update it when the rubric changes, and remove duplicate built-in records while preserving custom personas and historical review snapshots. Allow duplication and customization of rubric, focus, feedback depth, and additional instructions. Custom instructions cannot enable automatic manuscript edits. Academic reviews identify unsupported claims without inventing references.

### Panel

Add a toolbar toggle opening a trailing panel beside the document detail. Use a sheet in narrow layouts, retaining current minimum OS support through compatible layouts and availability checks.

The panel offers persona, provider/model, scope/root selection, optional Story Bible context, instructions, an input preview, and Run. Show progress and Cancel while running. Results show summary, findings, severity/category filters, evidence, rationale, and recommendations. Actions: Go to passage, Mark addressed, Dismiss, Add note. These actions do not modify prose.

History remains available offline, filters by target/persona/model/date/status, and shows the exact configuration and reviewed snapshot. Rerun creates a new linked review. Navigating elsewhere does not retarget an active run.

### Scope rules

- Scene/document: selected text document.
- Chapter: explicit container, its own text if present, then descendants in binder order.
- Novel: explicit manuscript root and ordered descendants; offer native novel/draft roots as defaults.
- Use section types to suggest roles, but show Document or Folder and descendants when classification is ambiguous. Do not infer roles solely from titles.
- Preview root, documents, word count, exclusions, and optional context before execution.
- Resolve from the data hierarchy, not the filtered binder. For manuscript-wide review, honor explicit includeInCompile=false by default, treat nil as included, and permit inclusion overrides. An excluded container does not automatically exclude eligible descendants.
- Exclude research, character cards, and non-text resources from manuscript input; include Story Bible context only when selected.
- Reject empty input. Include container text once. Validate project ownership and hierarchy cycles.

### Apple default and mature content

Use Foundation Models SystemLanguageModel through an availability-gated adapter. Check OS, device eligibility, Apple Intelligence enablement, and model readiness. A preference toggle alone does not establish readiness. If unavailable, explain the reason and offer settings; preserve the rest of the app on older OS versions.

Accept mature fictional text as material for analysis. Ask for literary critique, restrained evidence quotations, and respect for intended genre and tone. Do not add a blanket keyword block for violent or erotic source text. Treat manuscript-embedded instructions as data.

Apple's safeguards may reject mature content even for critique. Do not promise universal acceptance. Save refusals and partial coverage distinctly; allow an explicit retry with another configured model. Use only documented provider capabilities, and do not attempt to bypass safeguards. Verify current provider documentation and test representative mature-content critique cases before claiming support.

Apple reference: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
Safety reference: https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output

## Architecture

Add an AuthorAI package target with Sendable request/result types, provider adapters, model catalog, editorial prompts, and response validation. Keep AI requests outside SwiftUI and Core Data managed objects outside asynchronous service boundaries.

Use an EditorialReviewController for orchestration. WorkspaceController bridges selection and passage navigation rather than absorbing the full review subsystem.

Execution: flush pending editing changes; build immutable input snapshots; persist queued review; run asynchronous analysis; validate references and structured results; persist findings and coverage. Keep Core Data operations on its owning actor/queue. Cancel network/model work and save cancellation state. On relaunch mark abandoned running work interrupted; do not automatically resend manuscript text.

Validate every returned document reference and quote/range. Use explicit UTF-16 coordinates for native text navigation. Where ranges cannot be validated, retain a document-level finding rather than highlighting an invented location. Never execute model-supplied instructions, links, or tools.

For long inputs, budget model context and output, split at document/paragraph boundaries, checkpoint chunk results, then synthesize cross-document findings. Track input coverage and retain evidence through synthesis. Never silently truncate or call a summary-only pass a complete line edit. Validate quality on scene reviews before expanding to novels.

The existing user-supplied-key design needs no hosted backend. Add credential-aware native request adapters, bounded retries, cancellation, rate-limit handling, and structured decoding. Keep API keys in Keychain; surface failed Keychain writes. Exclude credentials and manuscript content from routine logs.

Support Apple Intelligence plus every configured external provider: OpenAI, Anthropic, Google Gemini, Mistral, xAI, and Cohere. Each provider has its own authenticated request adapter and structured JSON response contract; model-specific capability or account errors remain visible to the writer. OpenAI lists the GPT-family models enabled for the authenticated account, while the other providers retain explicit, independently saved model IDs so writers can select models their accounts support. Also support keyless local Ollama models through its default `http://127.0.0.1:11434` server and JSON-schema chat output. Local AI settings retain separate Junior Reviewer and Senior Reviewer model IDs. The Junior supplies candidate findings with evidence; the Senior verifies them against original text, omits rejected claims, and presents unresolved evidence as minor editorial questions. Junior passes retain the standard 1,200-token, 60-second budget; Senior passes receive a 2,400-token, 180-second budget so reasoning-heavy local models can emit their final schema-constrained review. Completed Ollama reviews can have an in-session, Senior-model discussion grounded in saved findings and evidence. Never silently switch providers or fall back to a different model.

## Persistence and migration

Add AuthorDataV5 after reconfirming V4 remains current. Preserve previous source and compiled model versions. Use typed, queryable fields rather than a single opaque response payload.

| Entity | Stored data |
| --- | --- |
| EditorPersona | UUID, preset key, name, rubric/instructions, version, built-in/custom flag, timestamps |
| EditorialReview | Project, optional live target, retained target UUID/title, scope, persona snapshot, provider/model identifiers, OS/app version where relevant, prompt/schema versions, parameters, summary, status, timestamps, error, usage when available, previous-run link |
| EditorialReviewInput | Review, optional live document, retained UUID/title/path/order, exact submitted text, content hash, manuscript/context role |
| EditorialFinding | Review, category, severity, title, explanation, recommendation, optional confidence, tracking status, user note, timestamps |
| EditorialFindingAnchor | Finding, input snapshot, evidence excerpt, optional validated range; multiple anchors per finding |
| EditorialReviewChunk | Review, stage/chunk identity, input membership and ranges, status, attempts, timestamps, errors, coverage and intermediate synthesis material |

Review states: queued, running, completed, partial, failed, refused, cancelled, interrupted. Finding states: open, addressed, dismissed. Derive completion from actual coverage and synthesis outcome.

Project deletion cascades to reviews; review deletion cascades to its owned records. Document/persona deletion nullifies live references while retained identities and snapshots preserve history. Keep model results immutable except explicit user tracking fields. Add provenance events for model runs. Do not auto-create annotations for all findings; promotion into an annotation can be a later user action.

Compare source hashes before passage navigation. Preserve old snapshots when text changes and show a stale-review indicator. Review snapshots are independent of document-owned Revision records, which can disappear with a document.

Enable inferred migration only after a migration test establishes it works. Regenerate AuthorData.momd using momc: SwiftPM copies the compiled resource, not the editable model. Test a populated V4 SQLite store opening in V5 and earlier supported versions. Fix the documentation that incorrectly labels V2 current.

## File-level work

Paths are relative to the Author repository.

| Existing path | Change |
| --- | --- |
| Sources/AuthorData/ManagedObjects.swift | Typed entities and inverse relationships |
| Sources/AuthorData/Persistence.swift | New repositories and review persistence integration |
| Sources/AuthorData/Resources/AuthorData.xcdatamodeld/ | V5 and .xccurrentversion |
| Sources/AuthorData/Resources/AuthorData.momd/ | Regenerated versioned models |
| Sources/AuthorUI/AuthorWorkspaceView.swift | Panel toggle and responsive presentation |
| Sources/AuthorUI/WorkspaceController.swift | Scope defaults, selection bridge, passage navigation |
| Sources/AuthorUI/DocumentContentView.swift | Validated range selection and pending-edit flush |
| Sources/AuthorUI/AIProviderSettings.swift | Default model resolution, readiness, Keychain error handling; depends on pending settings work |
| Sources/AuthorUI/AppPreferencesView.swift | Model defaults and provider availability; depends on pending settings work |
| Sources/AuthorUI/ProjectPreferencesView.swift | Manuscript-root/role configuration if needed; depends on pending settings work |
| Sources/AuthorApp/AuthorApp.swift | Inject review service/controller |
| Package.swift; AuthorApp.xcodeproj/project.pbxproj | Target/dependency/test wiring |
| Documentation/DataModel.md; README.md | Migration, scope, setup, history documentation |

New AuthorData files: EditorialManagedObjects.swift if preferable to extending the existing large file, ReviewScopeResolver.swift, ReviewSnapshotBuilder.swift, EditorialReviewRepository.swift.

New AuthorAI files: EditorialReviewService.swift, EditorialReviewTypes.swift, ModelCatalog.swift, EditorPromptBuilder.swift, ReviewResponseValidator.swift, AppleIntelligenceReviewClient.swift, OpenAIReviewClient.swift, ReviewChunkPlanner.swift.

New AuthorUI files: EditorialReviewController.swift, EditorPanelView.swift, EditorPersonaSettingsView.swift, ReviewHistoryView.swift, ReviewDetailView.swift.

Tests: extend AuthorDataTests and WorkspaceControllerTests; add EditorialPersistenceTests, ReviewScopeResolverTests, EditorialReviewControllerTests, and AuthorAITests with fake model clients. Change ScrivenerImporter.swift only if role mapping is required; do not transform imported prose.

## Staged implementation and acceptance gates

1. Baseline integration and data foundation. Integrate finalized prerequisite commits, add V5, personas, scope resolver, snapshots, repositories. Gate: old stores migrate without losing existing data; hierarchy/order/exclusion/deletion tests pass; no review process mutates manuscript text.
2. Apple scene-review milestone. Implement availability checks, structured critique, panel, history, cancellation/refusal/error persistence. Gate: eligible device completes and reopens a review; unavailable devices show accurate reasons; prose and rich-text bytes remain unchanged. Deterministic tests use a fake client; real-device validation separately checks Apple behavior.
3. Chapter and novel processing. Implement budgets, chunks, checkpointing, synthesis, optional Story Bible context, stale anchors, interrupted/partial runs. Gate: every included input is accounted for, oversized scenes work, retries do not duplicate findings, cancellation/relaunch preserve history, and results retain valid evidence.
4. External model choice and workflow completion. Implement OpenAI adapter, explicit model selection, configurable personas, finding status/notes, history filters and reruns. Gate: no silent provider switching, credentials remain protected, malformed outputs are handled, and mature-content acceptance/refusal is accurately reported per model.
5. Merge preparation. Run relevant data/UI/AI suites and supported-platform builds, manually inspect panel layouts and passage navigation, document limitations, and provide the final diff and validation summary. Leave merge approval to the user.

## Explicit exclusions

Automatic rewriting, replacement-prose generation, Apply All, autonomous manuscript edits, web hosting, team accounts, cloud sync, automatic cross-provider fallback, factual web research, and simultaneous support for every listed provider are outside this release.

## Approval checklist

Approve Apple-on-device default with explicit unavailable/refusal handling; the editorial-only contract; scene/chapter/novel scope semantics; V5 review history and snapshot retention; Apple plus one external adapter; and staged work on feat/ai-editor with a separate merge review.

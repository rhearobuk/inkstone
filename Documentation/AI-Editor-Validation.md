# AI Editor implementation and validation

Branch: `feat/ai-editor`.
Checkout: `/Users/robertrhea/Documents/Codex/Author-AI-Editor`.
Status: Implemented for branch review; not merged or pushed.

## Delivered

- Apple Intelligence on-device default when no other provider preference exists, actual availability checks, no silent cloud fallback.
- Explicit OpenAI model selection and a Responses API adapter with structured output, bounded HTTP retries, cancellation, Keychain credentials and error reporting. Account/model access errors remain visible.
- Six editorial presets and custom personas. Critique, evidence and recommendations only; no rewrite/apply actions.
- Scene/document, chapter/container and novel/root scope resolution with binder ordering, compile exclusions, preview and optional short Story Bible context.
- Responsive trailing panel/sheet, finding filters, passage navigation, addressed/dismissed state, user notes, history filters, rerun links and review deletion.
- V5 Core Data migration, immutable submitted-text snapshots, persona/model/configuration metadata, timestamps, reported usage where available, findings, anchors, chunk progress and provenance.
- Long-input section processing and hierarchical synthesis. Failed/refused sections preserve partial coverage. Cancellation and interrupted-app recovery do not resend content automatically.
- Debug `--editor-preview` launches an in-memory synthetic project without opening the saved project database.

## Validation performed

- Full suite with real local-model checks enabled: **34 tests, 33 passed, 1 opt-in rendering test skipped, 0 failures**.
- Apple ordinary synthetic scene review: passed with actual on-device inference.
- Apple mature-theme synthetic crime and adult-romance critique: passed. These short, non-graphic cases do not establish acceptance of explicit sexual or graphic violent manuscripts.
- Separate opt-in native panel rendering test: passed; native narrow-sheet layout also visually inspected in the isolated preview.
- Final UI suite after the rich-text navigation ordering fix: **19 tests, 18 passed, 1 opt-in rendering test skipped, 0 failures**.
- Mac and iOS/iPad simulator app builds: passed, including final incremental builds after the navigation ordering fix.
- V4 populated SQLite migration and reopening: passed, retaining original manuscript text and saved editorial snapshot/history. Existing V1/V2/V3 migration tests also passed against the current model.
- Scope ordering/exclusions/project ownership, Unicode chunk reconstruction, evidence validation, cancellation, interrupted recovery, persona immutability, history after document deletion and project cascades: passed.
- OpenAI transport/structured-response test: passed with an intercepted local request, including endpoint, authentication header, model, no tools and `store: false`. No paid cloud inference was performed by the validation suite.
- Source diff whitespace check: passed.

## Limits and follow-up review

- visionOS build could not run: the visionOS 26.5 platform is not installed. No SDK installation was attempted.
- Apple can return mistaken editorial judgments; findings must be checked against the cited text. The live test exposed an incorrect punctuation suggestion even though the output was structurally valid.
- Mature content may trigger provider refusals. Refusals are retained as such, never counted as a successful issue-free review.
- Novel processing is implemented and coverage-tested with fake clients. Full-length literary quality, latency and cost benchmarking remain product acceptance work; an entire real novel was not sent to any model during this task.
- Optional Story Bible context currently accepts one short entity summary. Oversized context is rejected explicitly, not silently shortened.
- Only Apple and OpenAI have review adapters. Other provider settings display an unavailable-adapter explanation in the editor.
- OpenAI account access, service behavior and charges require a user-configured API key. `store: false` does not promise zero provider retention.
- The initial prerequisite commit snapshots the original checkout's pre-existing uncommitted settings/workspace files. The original working folder was left unchanged. Before merging, reconcile any newer commits of that prerequisite work and review the migration on a backup of the intended production store.

## Commit structure

1. Planning document (`47452e8`).
2. Snapshot of existing prerequisite settings/workspace changes (`b733f8b`).
3. AI Editor implementation, tests and documentation (feature commit).

The feature branch is ready for code/product review after final build verification. Merging remains a separate user decision.

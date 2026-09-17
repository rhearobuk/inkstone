# App Store Submission Checklist

Submission target: **Inkstone 0.2.0, next build 38**. This is a preparation
checklist, not evidence that this version has been archived, uploaded, or tested.
It applies to macOS, iPadOS, and visionOS and supplements the current
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Add to this submission

1. Complete every owner-confirmation placeholder in
   [App Review Notes — 0.2.0](App-Review-Notes-0.2.md).
2. Paste that document's six numbered sections into **App Review Information
   → Notes**, and send the same completed text as the reply to Apple's
   **Guideline 2.1 — Information Needed** message. Include a working video
   attachment or reviewer-accessible link in both places.
3. Select the actual uploaded **0.2.0 (38)** build for each submitted platform.
   Confirm the archive's version/build, signing and entitlements; this document
   does not change project settings.
4. Confirm App Store Connect pricing, territories, age rating, screenshots,
   description and App Privacy answers against the submitted build. The README
   describes a planned free release and the sources have no IAP flow; neither
   establishes the actual App Store price.

## Physical-device evidence and QA

- Record the **submitted build**, beginning at launch, on a physical supported
  device running the latest publicly available OS for that platform. Identify
  device, OS version, app version/build and recording date in the notes.
- The [full UI walkthrough](UI-Walkthrough.md) runs the normal Release app:
  create a project, enter metadata, write and verify text after navigation,
  drag a scene into a folder, add a Story Bible place and render an export
  preview. It then uses normal Scrivener import (one manual picker selection
  on iPad/Vision Pro), opens **Ozma of Oz → The Girl in the Chicken Coop**,
  and requests **Apple Intelligence** critique with **Scene/document** scope:
  the target defaults to the selected imported document; verify its title.
  That chapter is one text document, not a folder of scenes. A completed review
  with a nonempty summary is required; refusal, partial coverage, unavailability
  and timeout are not passes. Export preview does not prove file saving/opening,
  and navigation away/back does not prove persistence after relaunch. Separately
  save and open the generated **DOCX, PDF and EPUB** files.
- Explain the absence of app registration/login, public social sharing and IAP; demonstrate
  those flows if the final product adds them. A disposable project's deletion
  can demonstrate data management; it is not account deletion.
- Apple Intelligence is the selected walkthrough provider; hardware, OS,
  language/region and model readiness still need physical-device confirmation.
  Show a real result or an honest unavailable/error state, never a staged reply.
  An error recording does not establish a successful full walkthrough.
  No external-provider credentials have been furnished for this route.
  Hide account identifiers, keys and notifications.
- Perform and record **your own QA on each supported physical platform**:
  Mac, iPad and Apple Vision Pro. Record device/OS/build, flows exercised, actual
  results and unresolved failures. Include startup, persistence, editing,
  import/export and production CloudKit sync; exercise AI where available and
  check unavailable-provider guidance. On iPad include orientation,
  multitasking, keyboard and accessibility; on Vision Pro include window sizing,
  text input, interaction and the layered icon.
- Apple's request does **not** explicitly require three separate videos or an
  exhaustive every-feature recording. Extra clips can clarify platform-specific
  behavior. Simulators, unit tests and UI automation supplement, not replace,
  physical-device QA and the requested recording.
- The walkthrough installs a locally built Release app, not necessarily the
  uploaded/TestFlight binary. Align source/version/build and repeat final QA
  and the recording on the actual submitted build.
- `Configuration/Inkstone-Walkthrough.xctestplan` now retains system and user
  attachments on success as well as failure, including available test video.
  Retention is not proof that a complete launch-to-finish physical recording
  exists or is suitable for submission: inspect the actual capture.

**Observed evidence status, September 17, 2026:** all three UI-test targets
compiled. Physical Mac core (84.6 seconds), Mac binder (96.0 seconds), and Vision
Pro core (82.4 seconds) passed and produced MP4s. Core and binder are now
independent tests. The Vision Pro drag attempt did not establish a hierarchy
move. iPad remains blocked by repeated XCTest animation waits.
Mac import succeeded, but no completed AI review was verified. Further runs
were stopped at the owner's cost limit. The edited Mac recording is in
`work/app-review-0.2/Inkstone-0.2-Mac-walkthrough.mp4`; it combines successful
runs, crops desktop content and redacts export contact details. Headset footage
is private raw material containing room passthrough. Review the final recording
and its build/launch coverage before submission; nothing has been uploaded.

Use original synthetic writing for the core flow. The user has authorized the
supplied untracked `The Wonderful World of Oz.scriv/` for local import and
Apple Intelligence review of the named chapter only. Do not copy/commit the full
package or use unrelated personal `Files/`/XML data. Local-use permission is not
proof of redistribution rights for the particular edition, images or resources:
confirm clearance before including excerpts in recordings or review attachments.

## Native functionality and AI privacy wording

Describe a native authoring app that works without AI, not just an API wrapper.
AI Editor adds explicit scope and persona, chunked manuscript review, response
validation, evidence links when quotations match the source, saved input
snapshots/review history, finding status/notes and explicit reruns linked to prior
reviews. Validation does not guarantee correct critique; the workflow never
automatically rewrites the manuscript.

Users control provider selection and supply their own cloud API keys, stored
locally in Keychain rather than project data/preferences. Requests go directly
to providers without a developer proxy, but those providers still receive the
selected text/context under their policies. BYOK is not a no-disclosure promise.
Apple Intelligence runs on-device. Ollama supports a privately run service on
the same Mac, currently hardcoded to `127.0.0.1:11434`; it is not a configurable
LAN/remote private-server feature. On iPad/Vision Pro, localhost means that device,
not the Mac. Editor requires Junior and Senior Reviewer model settings; Chat
uses Senior. Do not claim remote Ollama support or substitute it for the selected
Apple Intelligence walkthrough.

## Configuration and App Store Connect checks

- App target: macOS 14+, iPadOS 17+, visionOS 1+; iPad (`2`) and Apple
  Vision Pro (`7`), **not iPhone**, Apple Watch or Apple TV. Optional Apple
  Intelligence requires eligible hardware and OS 26+ with an available model.
- Archive and validate signed Release builds for each submitted platform.
  Verify App Sandbox/file access/network capabilities, production push
  entitlement and CloudKit container `iCloud.com.robertrhea.scribe`; verify its
  production schema and sync using non-personal test content.
- Inspect the final archive's `PrivacyInfo.xcprivacy` (UserDefaults reason
  `CA92.1`) and dependencies. Source configuration is not a signing or runtime
  validation result.
- Support URL:
  <https://github.com/rhearobuk/inkstone/blob/main/SUPPORT.md>.
  Confirm the published contact remains monitored:
  [example.quid-5d@icloud.com](mailto:example.quid-5d@icloud.com).
- Privacy Policy URL:
  <https://github.com/rhearobuk/inkstone/blob/main/Documentation/Privacy-Policy.md>.
  Check that both URLs are accessible to reviewers.
- Complete App Privacy answers from actual data handling and provider terms:
  review **Other User Content** (manuscript, Story Bible, annotations, reviews,
  chat), **Photos or Videos** for imported images, and **Contact Info** for
  author/agent details. Determine collection, identity linkage and tracking
  using Apple's definitions, retention and actual transmission paths; do not
  assume optional AI means “no data collected.”
- Confirm a reviewer-accessible route for optional AI without requiring the
  reviewer to buy a provider subscription or supply a paid API key. Keep any
  approved review access out of public documentation and recordings.

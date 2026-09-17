# Inkstone 0.2 walkthrough

The **Inkstone Walkthrough** Xcode scheme runs XCUITest against the normal
**Release** app. There are no mock AI replies, seeded database shortcuts, or
test-only app screens. The normal **Inkstone** archive scheme remains separate.

## What runs

| Mode | Automated flow and assertions |
| --- | --- |
| `core` | Launch; create a uniquely named project; enter multiword metadata and assert the trailing space survives; write a scene and verify it after navigating away/back; create and edit a Story Bible place; render a ready-to-export preview. |
| `binder` | Independently create a project, write a scene, create a folder and another scene, then drag that scene into the folder and verify its hierarchy. |
| `import-review` | Launch; import the supplied Scrivener project; open **Ozma of Oz > The Girl in the Chicken Coop**; request a real **Apple Intelligence** review of that one text document. A completed review with a nonempty summary is required. Refusal, partial coverage, unavailability, and timeout are not passes. |
| `full` | Run all three independent tests above. Each creates its own project and does not depend on another test's data. |

## Verified physical runs (September 17, 2026)

- Mac: core passed in 84.6 seconds; binder move passed in 96.0 seconds.
  Both have retained, playable MP4 recordings.
- Vision Pro: core passed in 82.4 seconds with a playable MP4. The separate
  drag attempt did not establish a hierarchy move. Headset footage includes
  room passthrough and inconsistent framing; keep the raw capture private.
- Mac Scrivener import succeeded in a later attempt, but the AI workflow did
  not complete. A subsequent attempt was stopped at the owner's cost limit.
- iPad: no completed physical run. No segmented iPad rerun was made.

The main core flow and binder are now separate, so a drag failure cannot
prevent recording the other features. A core pass does not imply a binder,
import, AI, saved-file export, or complete platform QA pass.

Export preview is not proof of saving/opening every output format. Import and
AI are not exercised by `core`. Neither mode proves iCloud synchronization,
all accessibility/input variations, or Vision Pro gaze/pinch usability.
**Physical-iPad automation is not yet reliable.** The core simulator run passed,
but physical runs repeatedly waited 60 seconds for animation completion and
eventually lost access to text-field snapshots. This occurred in both Story
Bible description and book metadata; removing the description step did not
resolve it, so that coverage was restored. The user confirmed the app responded
normally after stopping automation. Physical runs are paused pending diagnosis.
Do not treat these scripts as submission-ready physical recording automation.
They do not disable app animations or use private XCTest APIs to hide failures.

A subsequent controlled core retry also hit three 60-second animation waits
while entering Series Name. It verified `Harbor Stories`, including its space,
but timed out at the next field under an explicit four-minute test allowance.
This was not a completed physical walkthrough.

## Before running

- Use a clean test library/device or a separate macOS test account. These tests
  use the ordinary app and **create persistent projects**; with iCloud enabled,
  sample projects may synchronize. They never erase/reset a library or delete
  existing projects. Repeated runs add new projects.
- Do not run a recording against a library containing private manuscripts,
  author contact information, or API keys. Captures can include the sidebar.
- For physical devices: pair with Xcode, enable Developer Mode where required,
  unlock the device, and use the latest publicly released OS. Resolve signing
  in the app and UI-test targets using your development team.
- Full mode requires Apple Intelligence-capable hardware, a supported
  language/region, Apple Intelligence enabled and its model downloaded.
  Check its availability before recording. A simulator is not a substitute
  for this physical-device check.
- The supplied **The Wonderful World of Oz.scriv** package is deliberately not
  tracked in Git. On Mac, place it at the repository root. On iPad/Vision Pro,
  make the intact package available through Files before running. The test
  opens the file picker and allows three minutes for you to select it, then
  automatically performs the import. Do not choose an unrelated manuscript.
- Keep the source unchanged: the expected hierarchy is
  **Narrative > Manuscript > Ozma of Oz > The Girl in the Chicken Coop**.
  This chapter is imported as one text document, so **Scene/document** review
  covers the chapter without including siblings or the entire anthology.
- Close extra app windows and sheets. On Mac, allow Xcode/XCTest accessibility
  and automation access if prompted and give the app enough window space.
  iPad tests select landscape orientation.
- Keep the device unlocked and connected to power. Use the longest permitted
  Auto-Lock setting (five minutes on the current iPad): source selection allows three
  minutes; a review must finish within four minutes or the test cancels it
  and reports failure. Run `core` and `import-review` separately if preferred.
  Do not remove device security policies or tap app controls to keep it awake
  while XCTest is driving it.

## Run from Xcode

Select **Inkstone Walkthrough**, select a destination, and open Test Navigator.
Run `testCoreAuthoringWalkthrough` and
`testImportAndAppleIntelligenceWalkthrough` separately, or run the whole suite
to run both. The AI wait is capped at four minutes; a timeout is not a pass.

This installs a locally built Release app. It does **not** upload an archive,
install a TestFlight binary, or certify that it matches an uploaded build.
Keep the source/version/build aligned, and complete final QA on the actual
submitted/TestFlight build as Apple requested.

## Run from Terminal

Discover exact destinations:

```sh
xcodebuild -showdestinations -project AuthorApp.xcodeproj -scheme "Inkstone Walkthrough"
```

Replace `DEVICE_UDID` with the physical device identifier from that output:

```sh
bash Scripts/run-walkthrough.sh full \
  'platform=iOS,id=DEVICE_UDID'
```

Mac:

```sh
bash Scripts/run-walkthrough.sh full 'platform=macOS'
```

Vision Pro:

```sh
bash Scripts/run-walkthrough.sh full \
  'platform=visionOS,id=DEVICE_UDID'
```

For development, a simulator can exercise the core flow, not satisfy Apple's
physical-device evidence requirement:

```sh
bash Scripts/run-walkthrough.sh core \
  'platform=iOS Simulator,id=SIMULATOR_UDID' \
  work/ipad-walkthrough
```

The optional output directory must not already exist. Without it, a dated
directory is created under ignored `work/`. The script retains the log,
destination/configuration/source information, `.xcresult`, and exported
attachments, including named screenshots. Failure returns a nonzero status.
Leave simulator signing enabled: CloudKit requires the app's entitlements even
on a simulator. `CODE_SIGNING_ALLOWED=NO` builds can compile but crash at launch.
Do not commit recordings, result bundles, your source package, or credentials.

## Record for App Review

XCUITest drives the actions and Xcode records them automatically. The test plan
sets `preferredScreenCaptureFormat` to `video` and
`uiTestingScreenshotsLifetime` to `keepAlways`; system/user attachment retention
alone does not retain successful-run video. Successful Mac and Vision Pro MP4s
were exported and probed. No manual recording start/stop was needed for those runs.
Inspect framing, launch coverage and privacy before sharing any capture.

1. Prepare a clean library and the sample file, then close Inkstone.
2. Keep device/OS and version/build details for the accompanying notes.
3. Run `core`, `binder`, or `import-review` independently, or start `full`.
   On iPad/Vision Pro select the supplied file when prompted for import.
   Otherwise avoid interacting while XCTest runs.
4. Include launch, the main writing flow, the actual import, and the genuine
   Apple Intelligence response. Show the selected chapter and explain that
   the manuscript is not automatically rewritten.
5. Export and watch the recording. Confirm no private data, blocked dialogs,
   failures, or unrelated content appears. If an AI request fails, fix the
   prerequisite and make a fresh truthful recording rather than substituting
   a successful-looking response.
6. If the locally built binary differs from the submitted build, repeat this
   same checklist on the submitted/TestFlight build. Attach a reviewer-accessible
   video link/file and identify which platform/build was recorded.

Apple's supplied message asks for one physical-device typical-flow video,
not explicitly a video per platform or every function on every update.
It separately requires your own physical-device QA on each supported platform.
No automation result here should be described as App Review approval.

## Finish physical-device QA

Record results separately for Mac, iPad, and Vision Pro: actual build/OS,
date, device, pass/fail, and unresolved issues. Include cold launch and
persistence after relaunch; drag/drop and folder moves; text/formatting;
Story Bible description editing; import; file export and opening the generated DOCX/PDF/EPUB;
production iCloud synchronization; real Apple Intelligence availability and
failure handling; permissions; and relevant keyboard/touch/gaze/pinch behavior.

Use [App Review Notes 0.2](App-Review-Notes-0.2.md) for Apple's six requested
answers. Replace every bracketed placeholder and attach the sample and
physical recording before pasting into App Store Connect.

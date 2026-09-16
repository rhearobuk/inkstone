# App Store Submission Checklist

This checklist applies to the Scribe app target for macOS, iPadOS, and
visionOS. It supplements, but does not replace, the current
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Repository-complete items

- The target supports iPad (`2`) and Apple Vision Pro (`7`), not iPhone.
- App Sandbox, outgoing network access, user-selected read/write file access,
  CloudKit, and push notifications are configured.
- `APS_ENVIRONMENT` resolves to `development` for Debug and `production` for
  Release. Archive a signed Release build to verify that its provisioning
  profiles authorize production push notifications and
  `iCloud.com.robertrhea.scribe`.
- `PrivacyInfo.xcprivacy` declares the UserDefaults required-reason API with
  reason `CA92.1`. The app does not track users or include third-party SDKs.
- The published privacy policy is maintained in
  [Privacy Policy](Privacy-Policy.md).

## App Store Connect items

Complete these in App Store Connect for every released platform:

1. Enter the Support URL
   <https://github.com/rhearobuk/scribe/blob/main/SUPPORT.md>. It provides
   direct contact at
   [example.quid-5d@icloud.com](mailto:example.quid-5d@icloud.com).
2. Enter the Privacy Policy URL
   <https://github.com/rhearobuk/scribe/blob/main/Documentation/Privacy-Policy.md>.
3. Complete App Privacy answers from the actual release configuration. Review
   **Other User Content** for manuscript, Story Bible, annotation, review, and
   chat content transmitted to a selected cloud-AI provider. Review **Photos
   or Videos** when users import image files. Review **Contact Info** for
   author and agent details if they can be transmitted in a feature added to a
   release. State whether each type is linked to identity or used for tracking
   based on the provider configuration and contract in effect at submission.
4. In App Review notes, explain that cloud AI is optional, user-initiated,
   connects directly to the selected provider using a user-supplied API key,
   and can receive the request's selected text and context. Explain that Apple
   Intelligence is on-device and Ollama uses a local service.
5. Provide current support contact details and all review instructions needed
   to exercise CloudKit and each submitted feature. Do not require the
   reviewer to supply a paid AI key.

## Pre-submission validation

- Archive and validate signed Release builds for macOS, iPadOS, and visionOS.
- Test CloudKit synchronization using the production container on each
  platform.
- Test iPad portrait, landscape, Split View, Stage Manager, hardware keyboard,
  Dynamic Type, VoiceOver, and external-file import/export.
- Test the app on Apple Vision Pro or its simulator at different window sizes,
  including keyboard and pointer interaction.
- Validate the bundled `VisionAppIcon` layered asset on Apple Vision Pro before
  submitting a native visionOS build.
- Confirm the final app description, screenshots, age rating, support URL,
  and privacy answers describe the shipped app accurately.

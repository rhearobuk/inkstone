# Scribe Privacy Policy

**Effective date:** September 16, 2026

Scribe is an authoring application maintained by Robert Rhea. This policy
describes how the app handles data when used on macOS, iPadOS, and visionOS.

## Data stored by Scribe

Scribe stores the projects and information that a person enters or imports,
including manuscript text, Story Bible entries, annotations, review history,
imported project files, and images. It also stores author and agent contact
details when entered for export. This data is stored on the device.

When iCloud is available and Scribe is signed with its CloudKit capability,
project data is synchronized through the user's private iCloud database.
Author and agent settings are synchronized through the user's iCloud key-value
store. Scribe does not operate a developer-controlled account service, and the
maintainer does not receive this data.

## AI-assisted features

Cloud AI is optional and only runs after the user configures a provider and
starts a review or chat. The selected provider receives the text and context
needed to perform that request. Depending on the feature and choices made in
the app, this can include manuscript text, a Story Bible summary, project
context, and chat messages.

Scribe connects directly to the selected provider: OpenAI, Anthropic, Google,
Mistral, xAI, or Cohere. Those providers process data under their own privacy
terms and retention policies. OpenAI and xAI requests set `store: false`, but
that setting is not a promise of zero retention. Scribe does not send content
to a cloud provider automatically and does not provide a cloud fallback.

Apple Intelligence runs on-device when it is available. Ollama requests are
sent only to the local service at `127.0.0.1`.

API keys are stored in the system Keychain. They are not stored in Scribe's
project database, UserDefaults, or iCloud key-value store.

## Data sharing, tracking, and sale

Scribe does not include advertising, analytics, tracking, or a data broker
service. It does not sell personal data. The maintainer does not receive
project content or API keys. Data is shared with an AI provider only when the
user starts a request using that provider.

## User choices and deletion

Users choose whether to enter contact details, import images, enable iCloud,
or use an AI provider. Projects and their contained data can be moved to the
project trash and permanently deleted in the app. Author and agent details can
be cleared in Preferences. Deleting Scribe from a device does not remove data
from other devices or iCloud; users should delete projects in Scribe first.

## Contact and support

For private product-support and privacy requests, contact
[example.quid-5d@icloud.com](mailto:example.quid-5d@icloud.com). For product
support, bug reports, and feature requests, use the
[Scribe support channels](https://github.com/rhearobuk/scribe/blob/main/SUPPORT.md).
For security issues, follow the
[security reporting policy](https://github.com/rhearobuk/scribe/blob/main/SECURITY.md).

The public version of this policy is hosted at
<https://github.com/rhearobuk/scribe/blob/main/Documentation/Privacy-Policy.md>.

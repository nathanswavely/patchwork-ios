# Contributing

This is an early SwiftUI browsing prototype. Discuss substantial new features in an issue before implementing them, especially authentication, quilt discovery, and the custom quilt canvas.

Contributions to this repository are submitted under MPL 2.0. Only submit material you have the right to contribute under that license, retain existing notices, and add `// SPDX-License-Identifier: MPL-2.0` to new Swift files. Do not copy AGPL server or web implementation code into this client without first resolving the licensing implications.

Document the source and license of any added dependency or asset in PROVENANCE.md. Keep live community data, signing credentials, and personal Xcode settings out of commits.

Open Patchwork.xcodeproj and run Product → Test before submitting behavior changes. The UI tests use fictional `--preview` data; ordinary app launches connect to a quilt only after explicit selection. Keep direct-address connections available and do not preselect Lancaster.

If you change project.yml, regenerate the project with `xcodegen generate --spec project.yml` and commit the resulting project alongside the configuration.

Describe AI assistance in the pull request or commit message when applicable.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tooling

This project uses [Tuist](https://tuist.io) (v4.145.0, pinned via mise) for Xcode project generation. The `Tuist/Package.swift` manages third-party dependencies; `Project.swift` defines targets and build settings.

Install tools:
```bash
mise install
```

Fetch/update package dependencies:
```bash
tuist install
```

Generate the Xcode project:
```bash
tuist generate
```

After adding or removing source files, or changing `Project.swift` or `Tuist/Package.swift`, regenerate the project before building.

## Build & Test

Build from the command line (after generating):
```bash
xcodebuild -workspace ScoreEdit.xcworkspace -scheme ScoreEdit build
```

Note: `tuist xcodebuild build` does not pass `-workspace` to xcodebuild, so cross-project implicit dependencies (CeolKit sub-frameworks) are not resolved and the link step fails. Use the explicit workspace invocation above.

Run all tests:
```bash
tuist test
```

Run a single test target:
```bash
tuist test ScoreEditTests
```

## Project Structure

- `Project.swift` — Tuist project manifest. Defines the `ScoreEdit` app target (macOS) and the `ScoreEditTests` unit test target. Edit here to add targets, change bundle IDs, or add `dependencies`.
- `Tuist/Package.swift` — SPM dependencies consumed by Tuist. Add third-party packages here.
- `ScoreEdit/Sources/` — App source files (SwiftUI, Swift).
- `ScoreEdit/Tests/` — Unit tests using Swift Testing (`@Test`, `#expect`).
- `ScoreEdit/Resources/` — Asset catalogs and other bundle resources.
- `dist/` - Staging area for assembling the distributable artifact
- `scripts/` - Helper/utility scripts for this project

## Architecture

The app is a macOS-only SwiftUI application. At the time of this writing it is freshly scaffolded: `ScoreEditApp` is the `@main` entry point, and `ContentView` is the root view. There are no third-party dependencies yet.

Tests use the Swift Testing framework (not XCTest).

# snippingTool

A private macOS menu bar screenshot app inspired by Microsoft Snipping Tool.

## Current status

This repository currently contains the first implementation scaffold:

- SwiftUI macOS menu bar app shell
- capture coordinator and selection overlay
- permission checks for Screen Recording and Accessibility
- initial screenshot editor with simple annotation tools
- clipboard/save/export plumbing

## Requirements

- macOS 14+
- Full Xcode recommended for running and debugging
- Screen Recording permission for capturing other app windows/screens
- Accessibility permission for global shortcut support (later phases)

## Running locally

You can open the package directly in Xcode, or run it from the terminal.

### Fastest way right now

From the project root:

- `swift run snippingTool`

This launches the current menu bar app directly from the Swift package. The app has been verified to build successfully with `swift build`, and the direct launch path has been verified with `swift run snippingTool`.

### Using Xcode

- Open `Package.swift` in Xcode
- Let Xcode resolve the package
- Choose the `snippingTool` executable target
- Press Run

### Permissions on first launch

To capture the screen, macOS will require:

- **Screen Recording** permission
- **Accessibility** permission for global shortcut support

If you deny these the first time, you can re-enable them in:

- `System Settings > Privacy & Security > Screen Recording`
- `System Settings > Privacy & Security > Accessibility`

## Installation status

There is **no packaged `.app` installer yet**.

Right now, the project is a Swift Package with an executable target, so the practical ways to use it are:

- run it with `swift run snippingTool`
- run it from Xcode

If you want a normal drag-and-drop Mac app next, the next step is to create a dedicated Xcode macOS app target that builds a real `.app` bundle.

## Notes

Because this machine currently only has the Command Line Tools active, some GUI app workflows are best experienced by opening the package in full Xcode.

## UI automation groundwork

The app now includes the first pieces needed for click-through macOS UI tests:

- stable accessibility identifiers for key UI surfaces such as the menu bar item, settings window, overlay toolbar, and editor actions
- launch configuration flags to support a deterministic UI test mode

Supported app launch arguments:

- `--ui-testing`
- `--disable-global-hotkeys`
- `--ephemeral-defaults`

Environment variables can be used as equivalents when launching from a UI test runner:

- `SNIPPING_TOOL_UI_TESTING=1`
- `SNIPPING_TOOL_DISABLE_GLOBAL_HOTKEYS=1`
- `SNIPPING_TOOL_EPHEMERAL_DEFAULTS=1`
- `SNIPPING_TOOL_DEFAULTS_SUITE=<suite-name>`

For full user-click simulation on macOS, the remaining implementation step is still to add a native UI test host that launches a real `.app` bundle. That requires full Xcode rather than Command Line Tools alone.

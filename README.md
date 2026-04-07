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

- macOS 26+
- Xcode 26+ with Metal Toolchain installed
- Screen Recording permission for capturing other app windows/screens
- Accessibility permission for global shortcut support (later phases)

## Running locally

The project uses mlx-swift for on-device AI image descriptions, which requires Metal shaders. These shaders are **only compiled by Xcode's build system**, not by `swift build`/`swift run`.

### Quick start

After installing the Metal Toolchain, build and run with a single command:

```
./run.sh
```

This builds the project, kills any running instance, and launches the app.

### Manual build and run

1. **Install Metal Toolchain** (one-time):
   ```
   xcodebuild -downloadComponent MetalToolchain
   ```

2. **Build**:
   ```
   xcodebuild build -scheme snippingToolHost -destination 'platform=macOS' -configuration Debug
   ```

3. **Run**:
   ```
   open ~/Library/Developer/Xcode/DerivedData/snippingToolHost-*/Build/Products/Debug/snippingTool.app
   ```

### Using Xcode

- Open `snippingToolHost.xcodeproj` in Xcode
- Select the `snippingToolHost` scheme
- Press Run

### Why not `swift run`?

`swift build` / `swift run` cannot compile Metal shaders. Running the app built with SPM will crash with:
```
MLX error: Failed to load the default metallib.
```
Always use `xcodebuild` or Xcode instead.

### Permissions on first launch

To capture the screen, macOS will require:

- **Screen Recording** permission
- **Accessibility** permission for global shortcut support

If you deny these the first time, you can re-enable them in:

- `System Settings > Privacy & Security > Screen Recording`
- `System Settings > Privacy & Security > Accessibility`

## Installation status

There is **no packaged `.app` installer yet**.

Right now, the project is built via `xcodebuild` or Xcode using the `snippingToolHost` scheme.

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

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

> Local Xcode/DerivedData launches are meant for development only. macOS TCC permission retention is not reliable across rebuilt developer binaries.

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

## Keeping permissions across updates

macOS retains **Screen Recording** and **Accessibility** permissions based on the app's identity, not on anything stored by `PermissionManager`.

To keep permissions when updating:

1. Keep the same **bundle identifier**
2. Keep the same **signing identity / code requirement**
3. Replace the app **in place** at the same installed path, typically `/Applications/snippingTool.app`

This repository now pins the app's release version/build metadata in project settings and includes an install script for in-place release installs.

**Important:** a stable app path is not enough on its own. The release must also be signed with a real team identity. Ad hoc signed builds (`TeamIdentifier=not set`) will still lose TCC permissions across updates.

### Build and install a release update in place

Use:

```bash
./scripts/install-release.sh
```

That builds a `Release` app into a repo-local `.derived-data` folder and copies `snippingTool.app` to `/Applications/snippingTool.app`.

If your project is not already configured with a signing team in Xcode, pass one explicitly:

```bash
DEVELOPMENT_TEAM=YOURTEAMID ./scripts/install-release.sh
```

You can also install somewhere else explicitly:

```bash
./scripts/install-release.sh "$HOME/Applications/snippingTool.app"
```

For packaged releases, keep using the same destination path and the same signing identity when replacing the app.
The install script now refuses to copy ad hoc signed builds, because those cannot reliably retain Screen Recording and Accessibility permissions after an update.

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

There is **no auto-updater yet**.

Right now, the supported update path is an **in-place app replacement** using the same bundle identifier and signing identity. The repo includes `./scripts/install-release.sh` to make that flow repeatable.

Transient developer builds launched from Xcode or `DerivedData` are still supported for local work, but they are **not** the supported path for validating permission retention.

## Manual verification checklist for permission retention

1. Install a signed release build to `/Applications/snippingTool.app`
2. Launch it and grant **Screen Recording** and **Accessibility**
3. Build the next signed release with the same bundle identifier and signing identity (not ad hoc)
4. Replace `/Applications/snippingTool.app` in place
5. Relaunch and confirm the permissions remain granted in Settings and the onboarding flow does not ask again

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

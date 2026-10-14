<img width="128" height="128" alt="SimBuddy icon" src="https://github.com/user-attachments/assets/37184303-f58b-480e-8ae5-76a953ed3843" />

# SimBuddy

SimBuddy is a macOS tool that makes it easy to control and customize the status bar of Xcode simulators. It's ideal for developers and designers who need to simulate different status bar device states for screenshots or demos.

> Compatible with macOS Tahoe 26 and later.

<img width="1092" height="812" alt="SimBuddy" src="https://github.com/user-attachments/assets/db1c5f88-ece8-464b-bc6c-180d0632877d" />

## Features

- **Native macOS design:** A sidebar with your simulators grouped by runtime and a settings-style form under a Liquid Glass toolbar, following Apple's Human Interface Guidelines.
- **Menu bar control:** Quickly access main functions from the macOS menu bar icon.
- **Preset application:** Instantly set the simulator status bar to the classic "9:41, 100%, full bars" with a single click.
- **Multiple simulator management:** View all installed and running simulators, boot or shut them down, and apply changes to the ones you select.
- **Detailed customization:** Change time, battery state and level, Wi-Fi, cellular data, carrier, and other status bar items, with a live preview of the status bar.
- **File sharing:** Drop photos, videos, and documents onto the Sharing tray of the selected simulator. Images and videos go to the Photos app and everything else to the Files app, and files you shared to the Files app can be removed right from the tray.
- **Keyboard shortcuts:** ⌘R refreshes the list, ⌘O sends files to the selected simulator, ⌘↩ applies your changes and ⌘K clears them.
- **Automatic updates:** The simulator list stays in sync as simulators boot or shut down (you can turn this off in Settings).
- **Agent monitoring:** Track AI agent operations through a local MCP server, receive grouped notifications, and protect individual simulators from selected operations.

## Agent monitoring

Open **Agent monitoring** in the sidebar and enable it. SimBuddy requests notification permission, keeps a local history of up to 5,000 events, and continues monitoring when its main window is closed. SimBuddy must remain running in the menu bar. Notification permission is optional for history and protection.

Select a simulator and enable **Protect from agents** in its detail panel. Protection is saved by UDID, independently of sidebar selection. The default blocks shutdown, reboot, deletion and data erasure. You can separately allow or block queries, booting, apps, tests, captures, settings and content operations. Rules apply to every affected device, including paired watches and phones. A batch containing a protected target is refused before execution.

**Protection covers operations requested through SimBuddy’s MCP server.** Commands executed directly through Terminal, Xcode, another MCP server or another connector cannot be blocked by this integration. External polling observes state changes and devices appearing/disappearing from the available list, with an unknown source. It cannot reliably identify an AI agent, detect data erasure, or capture transitions between its 3-second samples. State observations during a managed operation are folded into that operation’s history.

Tests have their own permission and are allowed by default. Allowing tests authorizes `xcodebuild` and project scripts to run; they may modify or restart the destination internally. Protection does not intercept those internal actions.

### Connect an MCP client

Choose **Configure MCP…** in Agent monitoring to copy configuration with the current app path. For clients that use a `mcpServers` JSON object, a typical configuration is:

```json
{
  "mcpServers": {
    "simbuddy": {
      "command": "/Applications/SimBuddy.app/Contents/MacOS/simbuddy-mcp"
    }
  }
}
```

Use the client’s equivalent stdio configuration if its format differs. Instruct your agent to use SimBuddy’s tools for simulator operations. Configuration does not redirect the agent’s other tools automatically. Connection names are self-reported by MCP clients, not verified identities.

The connector is bundled with the app and uses the official Swift MCP SDK. It forwards requests over a Unix socket in a directory restricted to the current user. It cannot execute simulator commands independently. Closing SimBuddy makes tool calls fail; disabling monitoring rejects new operations without interrupting running ones. Operation status and cancellation remain available to the owning session after monitoring is disabled.

### MCP tools and coverage

| Tool | Purpose |
| --- | --- |
| `list_simulators` | Available devices, states and saved protection rules |
| `describe_operations` | Supported operation names, categories and required/optional parameters |
| `execute_operation` | Submit a classified simulator operation; returns an operation ID |
| `run_tests` | Run `test` or `test-without-building` on one explicit destination |
| `get_operation` | Status, bounded stdout/stderr and result bundle path for this session |
| `cancel_operation` | Cancel a queued operation or stop its running process group |

Operation inputs contain `operation`, `devices` (UDIDs) and `parameters` (named strings). `all` and `booted` expand into explicit available UDIDs before authorization. Captures and tests require one device; pairing requires explicit watch and phone UDIDs in that order. `unpair` and `pair_activate` use `pairID`. File paths must be absolute. Unknown parameters are refused, and rules are rechecked before queued operations execute.

The catalog covers boot/shutdown/reboot, creation/cloning/renaming/deletion/erasure, pairing, installed app queries and containers, app installation/launch/termination, app data replacement, photos/media, URLs, clipboard, simulated pushes, screenshots/video, location scenarios/waypoints, privacy permissions, status bar overrides, appearance/contrast/text size, screen configuration, keychain certificates/reset and verbose logging. New Xcode subcommands are refused until classified. Arbitrary `spawn`, alternate device sets, global runtime management and unclassified commands are unavailable.

Clipboard writes are read back for verification. Some Xcode runtimes report success from `simctl pbcopy` without retaining the text; SimBuddy reports these writes as failed instead of confirming an empty clipboard.

Example `execute_operation` arguments:

```json
{
  "operation": "screenshot",
  "devices": ["SIMULATOR-UDID"],
  "parameters": { "path": "/tmp/simulator.png" }
}
```

For `run_tests`, provide `devices` with one UDID and `parameters` containing `projectPath` (`.xcodeproj` or `.xcworkspace`) and `scheme`. Optional parameters are `action` (`test` or `test-without-building`), `onlyTesting` and `skipTesting` (comma-separated test identifiers). SimBuddy supplies the destination, disables parallel testing, and creates a unique `.xcresult` path. There is no free-form argument field.

All categories notify by default. Events from the same devices and session are grouped over 3 seconds; blocks and failures notify immediately. Use **Categories** to mute selected categories. Clicking an alert opens its history event. History includes operation names, timestamps, session names, affected simulators and outcomes; payloads, clipboard contents and process output are not persisted. Bounded process output is available in memory for the latest 100 completed operations until the app exits. Test result bundles remain in `~/Library/Application Support/SimBuddy/Agents/Results` for inspection.

### Development and validation

Build the `SimBuddy` scheme to build and embed `simbuddy-mcp` automatically. The shared scheme includes standalone macOS monitor tests that do not launch the app or touch real simulators.

```sh
swift test --package-path AgentIntegration
xcodebuild -project SimBuddy.xcodeproj -scheme SimBuddy -destination 'platform=macOS' test
```

The optional `disposableSimulatorSmokeTest` runs only with `SIMBUDDY_SMOKE_TESTS=1` in the test runner’s environment. It requires the iOS 27.0 runtime and iPhone 16 device type, creates its own simulator, verifies protection/capture/clipboard/settings, and removes only that device. Set `SIMBUDDY_SMOKE_PROJECT` to a disposable iOS project with a shared `Smoke` scheme to also exercise `run_tests`.

## Available Languages

- Bulgarian (bg)
- Danish (da)
- German (de)
- Greek (el)
- English (en)
- English (Australia) (en-AU)
- English (Canada) (en-CA)
- English (United Kingdom) (en-GB)
- English (India) (en-IN)
- English (Philippines) (en-PH)
- Spanish (es)
- Spanish (Latin America) (es-419)
- Spanish (United States) (es-US)
- Finnish (fi)
- French (fr)
- French (Canada) (fr-CA)
- Hungarian (hu)
- Italian (it)
- Japanese (ja)
- Korean (ko)
- Norwegian Bokmål (nb)
- Dutch (nl)
- Polish (pl)
- Portuguese (Brazil) (pt-BR)
- Portuguese (Portugal) (pt-PT)
- Russian (ru)
- Swedish (sv)
- Ukrainian (uk)
- Chinese (Simplified) (zh-Hans)

> Help the project by adding a missing translation!

## Installation

You can download the latest version [here](https://github.com/AugustoBSimionato/SimBuddy/releases). This will download a file named `SimBuddy.dmg`. Open it and move the app to your Applications folder.

## License

This project is licensed under the [MIT License](LICENSE).

---

Contributions are welcome! Feel free to open issues or pull!

Created by [@gutobaroni](https://www.threads.com/@gutobaroni) in Brazil 🇧🇷

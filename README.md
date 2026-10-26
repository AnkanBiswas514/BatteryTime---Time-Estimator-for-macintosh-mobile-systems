<div align="center">

# BatteryTime

### Know your battery. Plan your time.

**A lightweight, privacy-first battery time estimator for macOS — right in your menu bar.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-111827?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![CI](https://github.com/AnkanBiswas514/BatteryTime---Time-Estimator-for-macintosh-mobile-systems/actions/workflows/ci.yml/badge.svg)](https://github.com/AnkanBiswas514/BatteryTime---Time-Estimator-for-macintosh-mobile-systems/actions)

[Features](#features) · [Get started](#get-started) · [How it works](#how-it-works) · [Development](#development) · [Limitations](#limitations--accuracy)

</div>

---

## Overview

BatteryTime estimates **how long your Mac can keep going** based on observed battery energy changes, rather than relying on battery percentage alone. It lives in the menu bar, adapts to changing power consumption, and helps you decide whether your current battery will last for the work ahead.

Everything runs locally. There are no accounts, cloud services, analytics SDKs, or external runtime dependencies.

> **Project status:** Active development / preview. The portable estimation tests have been run, but this version's complete macOS app has **not yet been verified with an Xcode build or a real-device launch**. Estimates are informative, not guarantees.

## Features

| Feature | What it does |
| --- | --- |
| **Live time remaining** | Estimates active battery runtime from recent changes in stored energy. |
| **Power draw and charging rate** | Displays estimated watts derived from battery capacity measurements. |
| **Smoothed predictions** | Uses short- and long-window calculations to reduce noisy estimates. |
| **Confidence range** | Shows a heuristic estimate range and a qualitative confidence label. |
| **Battery budget** | Compares current power draw against a target runtime you choose. |
| **Workload indicator** | Classifies power-demand intensity based on observed drain, without inspecting which apps you use. |
| **Power history** | Plots recent battery draw and flags significant drain increases. |
| **Adaptive sampling** | Adjusts refresh intervals to reduce unnecessary work. |
| **Charging estimate** | Estimates time to full with a conservative taper adjustment. |
| **Battery capacity history** | Stores limited local snapshots of reported full-charge capacity. |
| **Low Power Mode** | Reads and can change the macOS setting, subject to system authorization. |
| **Customizable menu bar** | Choose which indicators appear beside the battery icon. |

## Get started

### Requirements

- A Mac running **macOS 13 Ventura or later**
- **Xcode 15 or later** for building from source
- An internal battery for battery-energy-based features (desktop Macs have limited support)

### Build and run in Xcode

1. Download or clone this repository.
2. Open **`BatteryTime.xcodeproj`** at the project root. **XcodeGen is not required.**
3. Select the **BatteryTime** scheme and **My Mac** destination.
4. If Xcode requests a signing team, choose one under **Signing & Capabilities**. For local development, Xcode may be able to use local signing.
5. Press **⌘R** to build and launch.
6. Look for BatteryTime in the **macOS menu bar**, not the Dock. The app is configured as a menu-bar-only utility.

### Install the built app in Applications

Once the Xcode build succeeds:

1. In Xcode, choose **Product → Show Build Folder in Finder**, or locate the compiled app in **Products** and select **Show in Finder**.
2. Copy **`BatteryTime.app`** (the compiled app bundle, **not** the `.xcodeproj` file or source folder) into `/Applications`.
3. Launch it with Finder or run `open /Applications/BatteryTime.app`.
4. Check the menu bar for its icon and readings. There is intentionally no Dock icon or standard main window.

If the app does not launch, check **System Settings → Privacy & Security** for a security prompt and see [Troubleshooting](#troubleshooting). Copying an unsigned development build to another Mac may require additional signing or notarization.

## How it works

BatteryTime reads available macOS power-source information using **IOKit**. Where supported, it derives approximate stored energy from battery capacity and voltage readings. It measures how energy changes over time and uses a portable Swift estimation engine (`BatteryCore`) for smoothing and runtime calculations.

```text
macOS battery information (IOKit)
               │
               ▼
        BatteryReading
               │
               ▼
         BatteryModel ───────► local history / settings
               │
               ▼
        BatteryCore estimator
               │
               ▼
       SwiftUI menu bar popover
```

For a simple intuition, estimated runtime is approximately:

```text
remaining runtime (hours) ≈ remaining energy (Wh) / average discharge power (W)
```

Real-world consumption changes constantly. BatteryTime uses recent observations and smoothing, so a prediction can shift when you start a demanding task, change brightness, or connect a charger.

### Battery budget

Choose how many hours you want your battery to last. BatteryTime calculates an approximate average power allowance:

```text
allowed average draw (W) = remaining energy (Wh) / target runtime (hours)
```

It then indicates whether your measured discharge rate is above or below that allowance. This is guidance, **not** an automatic power-management feature.

## Settings

Open the menu bar popover and select **Settings…** to configure:

- Battery icon style and visible menu bar indicators
- Averaging window and minimum learning time
- Target runtime for Battery Budget

Some values may initially show **Learning**, **Calculating…**, or **Unavailable** while BatteryTime gathers enough usable measurements.

## Development

The repository contains both an Xcode app project and a platform-independent Swift package for estimator testing.

```text
BatteryTime.xcodeproj/       Xcode project and shared scheme
Sources/
  BatteryTime/              SwiftUI app, model, IOKit reader, preferences
  BatteryCore/              Pure Swift estimation engine
Tests/
  BatteryCoreTests/         Estimator unit tests
.github/workflows/ci.yml   Swift tests and macOS build workflow
Package.swift              Swift package manifest for BatteryCore
project.yml                Optional XcodeGen configuration
```

Run the core tests:

```bash
swift test
```

Build the macOS app from Terminal (requires Xcode):

```bash
xcodebuild \
  -project BatteryTime.xcodeproj \
  -scheme BatteryTime \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

`CODE_SIGNING_ALLOWED=NO` is suitable for checking compilation in CI; it does **not** produce a signed distribution release. The included GitHub Actions workflow runs the test suite and attempts this build on a macOS runner.

## Privacy

BatteryTime is designed to keep its measurements on your Mac:

- No sign-in, cloud sync, telemetry, or third-party analytics
- No application-usage attribution or process surveillance
- Estimation history and settings stored locally using `UserDefaults`
- No network connection required for core functionality

## Limitations & accuracy

BatteryTime aims to make battery behavior understandable, but there are important caveats:

- **Not a hardware wattmeter:** Reported power draw is inferred from battery energy changes, not measured directly as whole-system wall power.
- **Hardware differences:** Some Macs or macOS versions may not expose the required battery properties.
- **Confidence is heuristic:** The displayed range is not a statistically calibrated probability interval.
- **Workload labels are approximate:** They describe observed power demand, not which app or process caused it.
- **Charging is nonlinear:** Charging can slow substantially near full; time-to-full predictions may drift.
- **Capacity history is not a diagnosis:** Battery capacity snapshots are not a verified health or degradation assessment.
- **Sleep and short sampling windows:** The app excludes sleep-related discontinuities where detected and needs time to learn after startup or power-state changes.

## Troubleshooting

**I launched the app, but no window or Dock icon appeared.**  
That's expected: BatteryTime is a menu bar app. Check the top-right menu bar and Activity Monitor.

**Terminal says `No such file or directory`.**  
Confirm that you copied the **compiled** `BatteryTime.app` bundle to `/Applications`. Run:

```bash
ls -ld /Applications/*BatteryTime*
ls -la /Applications/BatteryTime.app/Contents/MacOS/
```

If the first command finds a differently named app, adjust the path. If the executable directory is missing, rebuild and copy the actual `.app` product from Xcode.

**The app is blocked by macOS.**  
Review **System Settings → Privacy & Security** and the system's security message. For distribution to other users, proper signing and notarization are recommended; don't disable macOS security globally.

**The estimate says Calculating or Unavailable.**  
Keep the Mac awake and unplugged for several minutes, and check that its battery information is accessible. Some hardware does not provide the energy fields this estimator needs.

**Low Power Mode does not change.**  
macOS may require administrator approval, and support can vary by hardware and OS version.

## Contributing

Bug reports, documentation improvements, reproducible power traces, and estimator test cases are welcome. When opening an issue, include your macOS version, Mac model, the behavior you expected, and what actually happened. Avoid sharing personally identifying system information.

For code changes, keep the estimator testable, prefer native macOS APIs, and avoid adding network dependencies to the core app.

## License

**A license has not yet been selected for this repository.** Until the copyright holder adds an explicit license, standard copyright restrictions apply. A license should be chosen before inviting code reuse or redistribution as an open-source project.

---

<div align="center">

**BatteryTime** · Native macOS battery insights, without the cloud.

[Back to top](#batterytime)

</div>

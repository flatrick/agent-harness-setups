---
name: uno
description: Build the unoplatform/uno repo (src/*.slnf) — what workloads/toolchains are required per platform, what one-time setup is needed, which solution filters build clean on Linux vs. what Windows additionally unlocks, which need project exclusions, and why. Use whenever building, restoring, or diagnosing a failed build/restore under unoplatform/uno's src/ directory, or scoping what a given OS can build.
---

# Building unoplatform/uno

Primary findings are from a from-scratch build attempt on a Linux (WSL2) box with the `10.0.111` .NET SDK,
no Android SDK installed, and no Windows/macOS toolchain available. The Wasm, UnitTests, and Skia filter
results were independently re-verified on Windows 11 with .NET SDK `10.0.303` (see "Per-`.slnf` results"
and the Windows Skia subsection below) — those are tested fact, not transcribed docs. Everything else under
"Building on Windows" (workloads, VS prerequisites, the WinUI/Windows-native target, gotchas) is still
derived from the repo's own `doc/articles/uno-development/building-uno-ui.md` and
`build/ci/templates/dotnet-mobile-install-windows.yml`, not independently exercised — treat those parts as
directions, not tested fact, and re-check against the live docs if something doesn't match. Re-verify if the
repo's build system (`AGENTS.md`, `.claude/rules/build-system.md`) has changed materially since.

## Required workloads / toolchains, per target

| Target | `.NET` workload(s) | Extra toolchain needed | Linux? | Windows? |
|---|---|---|---|---|
| Skia (Desktop Win32/macOS/Linux, Skia-on-Android/iOS/WASM) | none (plain SDK) | — | ✅ | ✅ |
| WebAssembly | `wasm-tools` | — | ✅ | ✅ |
| Android (native or Skia-on-Android app head) | `android` | **Android SDK** (platform-tools, build-tools, platform APIs) — a separate install from the workload itself | ✅ workload; ❌ SDK not installed here | ✅ (via VS's Tools ▸ Android ▸ Android SDK Manager, or `uno-check`) |
| iOS / tvOS / macCatalyst | `ios` / `maccatalyst` / `tvos` | Xcode + **a Mac build host** to actually compile native output | ❌ not installable at all | ⚠️ workload installs, but compiling still needs a *paired Mac* — Windows alone cannot produce the final native binary |
| Windows (UWP/WinAppSDK native) | n/a (VS workload, not a `dotnet workload`) | Visual Studio **UWP Development** workload + Windows 10/11 SDK ≥ `19041` | ❌ | ✅ |
| Reference / UnitTests / Tools / RemoteControl (non-mobile) | none | — | ✅ | ✅ |

Install/verify `dotnet` workloads:
```
dotnet workload install wasm-tools android      # sudo on Linux (dotnet is root-owned there)
dotnet workload list                            # verify — see the registration gotcha below
```
The **officially recommended** way to provision a dev machine (any OS) is the
[`uno.check`](https://github.com/unoplatform/uno.check) tool, which the repo's own CI uses on Windows:
```
dotnet tool update --global uno.check
uno-check --fix --tfm net10.0-android --tfm net10.0-ios --tfm net10.0-maccatalyst --tfm net10.0-tvos
```
(the CI job skips `--skip androidemulator --skip xcode --skip gtk3 --skip maui --skip vswin --skip vsmac
--skip unosdk --skip dotnetnewunotemplates` in its own non-interactive run — a local run without those skips
will also try to provision Android emulators / Xcode / VS component installs).

## One-time setup

1. **`crosstargeting_override.props` does not exist by default, on any OS** — copy it (verified identically
   on both Linux and Windows):
   ```
   cd src
   cp crosstargeting_override.props.sample crosstargeting_override.props
   ```
   It's gitignored (per-developer, never commit it — confirmed by `.claude/rules/build-system.md`).

2. Set inside it (same on Windows and Linux):
   ```xml
   <UnoTargetFrameworkOverride>net10.0</UnoTargetFrameworkOverride>
   <UnoFastDevBuild>true</UnoFastDevBuild>
   ```
   `net10.0` (no platform suffix) is correct for **Skia, WebAssembly, Reference, RemoteControl (non-mobile), UnitTests, Tools**. Switch it to `net10.0-android` only for an Android-specific pass (see below) — never leave the solution "open" across a switch per the WARNING in the props file; not applicable to CLI-only workflows but do a clean `--no-restore`-free restore after switching.

3. **Workloads (Linux only step)**: `dotnet` here is root-owned (`/usr/sbin/dotnet` → `/usr/share/dotnet`), so workload commands need `sudo`:
   ```
   sudo dotnet workload install wasm-tools android
   ```
   `ios`/`maccatalyst`/`tvos` workloads are **not installable on Linux** at all.

   **Gotcha**: after installing, `dotnet workload list` can show **zero installed workloads** even though the
   packs actually landed on disk (check `/usr/share/dotnet/metadata/workloads/InstalledPacks/v1`) — the
   registration record can end up missing/incomplete (e.g. if the install was interrupted). Symptom: build
   still fails with `NETSDK1147: workload 'wasm-tools' must be installed` despite the packs being present.
   Fix:
   ```
   sudo dotnet workload repair
   ```
   Verify with `dotnet workload list` before trusting a "missing workload" error as real.

4. **Linux only**: always pass `-p:AllowMissingPrunePackageData=true` to `dotnet restore`/`dotnet build` on
   this SDK/TFM combo — otherwise `Uno.UI.RemoteControl.Host.csproj` (net10.0) fails restore with
   `NETSDK1226: Prune Package data not found .NETCoreApp 10.0 Microsoft.AspNetCore.App`. Verified unnecessary
   on Windows (SDK `10.0.303`) — `Uno.UI-Wasm-only.slnf` and `Uno.UI-UnitTests-only.slnf` both restored and
   built clean there with no such flag.

5. **Android SDK is a separate, larger install** from the `android` .NET workload. The workload alone
   gets you Android *library* projects working; `Uno.UI.Runtime.Skia.Android` and any `netcoremobile`
   Android head/app project still need an actual Android SDK (`ANDROID_HOME`/`ANDROID_SDK_ROOT` +
   platform-tools/build-tools), which was not present and not installed as part of this work. Without it,
   Android builds fail with `XA5300: The Android SDK directory could not be found`.

## Per-`.slnf` results (net10.0 override, wasm-tools + android workloads registered, no Android SDK)

| Filter | Linux result | Windows result |
|---|---|---|
| `Uno.UI-Wasm-only.slnf` | **Clean, no exclusions.** | **Clean, no exclusions** (verified, SDK `10.0.303`, 4 pre-existing NuGet-version-conflict warnings in `SamplesApp.UITests`, unrelated to platform). |
| `Uno.UI-UnitTests-only.slnf` | **Clean, no exclusions.** `dotnet test`/`dotnet run` on `Uno.UI.UnitTests` can still fail at runtime (not build) — see below. | **Clean, no exclusions, 0 warnings** (verified). |
| `Uno.UI-Tools.slnf` | **Clean, no exclusions.** | Not independently verified. |
| `Uno.UI-Skia-only.slnf` | Clean **after excluding 4 project entries** (see below). | **Restore fails as-is** (same stale entry as Linux — see below); clean build achieved after a different, larger exclusion set — see the Windows subsection below. |
| `Uno.UI-Reference-Only.slnf` | 22/24 clean; 2 fail (see below). | Not independently verified. |
| `Uno.UI-RemoteControl-Only.slnf` | 37/42 clean; 5 `netcoremobile`-suffixed projects fail (see below). | Not independently verified, but the same `netcoremobile`-under-plain-`net10.0` failure mode was independently reproduced on Windows via the Skia filter (see below), so expect the same 5 failures. |
| `Uno.UI-netcoremobile-only.slnf` | Not buildable without an Android SDK (Android) / at all on Linux (iOS/tvOS/macCatalyst). | Not independently verified. |
| `Uno.UI-Windows-only.slnf` | Not buildable on Linux at all. | Not independently verified (needs the VS UWP workload — see below). |

### `Uno.UI-Skia-only.slnf` on Linux — exclude these 4 project entries

- `AddIns/Uno.UI.Lottie/Uno.UI.Lottie.Tests.csproj` — **listed in the `.slnf` but does not exist** on disk or
  in `Uno.UI.slnx` (stale repo inconsistency, not caused by any local setup, and **confirmed to reproduce
  identically on Windows** — restore fails immediately with `MSB4025` there too). Restore fails immediately
  with `MSB4025` if left in.
- `Uno.UI.Runtime.Skia.AppleUIKit`, `Uno.UI.Runtime.Skia.MacOS`, `Uno.UI.Runtime.Skia.Win32*` — need
  Mac/Windows toolchains, not available on Linux. (`AppleUIKit` also transitively drags in
  `Uno.netcoremobile.csproj`, which then fails to build under a plain `net10.0` override — see the CS0116
  note below.) On Windows, the `Win32*` entries don't need excluding — see below.
- `Uno.UI.Runtime.Skia.Android/Uno.UI.Runtime.Skia.Android.csproj` — fails restore with `NU1015: The
  following PackageReference item(s) do not have a version specified: Xamarin.AndroidX.AppCompat`. Pre-existing
  repo issue, independent of workload/SDK availability — reproduces even with the `android` workload
  correctly registered, and **confirmed to reproduce identically on Windows**.
- `AddIns/Uno.UI.Maps/Uno.UI.Maps.netcoremobile.csproj` — fails restore with `NU1201`: resolves to
  `net9.0-android` instead of `net10.0-android` even with `UnoTargetFrameworkOverride=net10.0-android` set.
  Pre-existing repo TFM-resolution bug, **confirmed to reproduce identically on Windows**.
- Also exclude `SamplesApp/SamplesApp.Skia.WebAssembly.Browser/SamplesApp.Skia.WebAssembly.Browser.csproj`
  when building it *inside* the Skia filter — it builds fine standalone inside `Uno.UI-Wasm-only.slnf`, but
  inside `Uno.UI-Skia-only.slnf` it triggers `MSB4057: The target "GetCopyToPublishDirectoryItems" does not
  exist` on `Uno.UI.Reference.csproj`, a filter-context-dependent MSBuild target-resolution issue. Since
  `Uno.UI-Wasm-only.slnf` already covers it cleanly, just exclude it here rather than debug the interaction.
  **Confirmed to reproduce identically on Windows.**

### `Uno.UI-Skia-only.slnf` on Windows — verified exclusion set (differs from Linux)

Verified end-to-end on Windows 11, SDK `10.0.303`, using the JSON-editing technique below to build a local,
untracked copy of the filter. Restore of the unmodified `.slnf` fails immediately on the same stale
`Lottie.Tests` entry as Linux (not a Linux-only problem — it's a `.slnf`/`.slnx` drift, so it breaks restore
on every OS). Once past that, Windows needs a **different exclusion set than Linux**, verified by iterating
project-by-project rather than assumed:

- **`Uno.UI.Runtime.Skia.Win32` / `Uno.UI.Runtime.Skia.Win32.Support`**: unlike Linux, these do **not** need
  excluding — Windows is their native platform and they build clean. So excluding "all `Win32*`/`AppleUIKit`/
  `MacOS` entries" as a blanket rule is Linux-specific; on Windows only `AppleUIKit` and `MacOS` still need
  excluding (they need an actual Mac toolchain, which Windows doesn't have either).
- **Every `*.netcoremobile.csproj` entry present in this filter must be excluded**, not just the ones Linux's
  4-entry list called out. The filter includes several beyond `Uno.UI.Maps.netcoremobile` — e.g.
  `Uno.UI.Foldable.netcoremobile`, `Uno.UI.GooglePlay.netcoremobile`, `Uno.UI.MSAL.netcoremobile`,
  `SamplesApp.Skia.netcoremobile` — and each one drags `Uno.UWP/Uno.netcoremobile.csproj` into the build via
  a `ProjectReference` that a `.slnf` filter cannot suppress (filtering only controls which projects MSBuild
  loads as entry points, not their transitive references). Under the plain `net10.0` override that reference
  fails with the same `CS0116: A namespace cannot directly contain members such as fields, methods or
  statements` already documented under `Uno.UI-RemoteControl-Only.slnf`'s 5 known failures below — this is
  the same structural "`netcoremobile`-suffixed projects don't build under a non-mobile TFM override" issue,
  just also reachable from the Skia filter, not only the RemoteControl one. Excluding `Uno.UI.Maps.netcoremobile`
  alone (Linux's approach) isn't sufficient on Windows because the *other* `netcoremobile` entries are still
  present and still resolve their own transitive reference.
- With `Lottie.Tests`, `Uno.UI.Runtime.Skia.Android`, `Uno.UI.Runtime.Skia.AppleUIKit`,
  `Uno.UI.Runtime.Skia.MacOS`, `SamplesApp.Skia.WebAssembly.Browser`, and **all** `*.netcoremobile.csproj`
  entries excluded (6 exclusion patterns, ~15 of the 92 listed projects), restore and build both went clean:
  0 errors, 3 pre-existing warnings unrelated to the exclusions.

### `Uno.UI-Reference-Only.slnf` — 2 known failures

`SourceGenerators/XamlGenerationTests/XamlGenerationTests.csproj` and
`SourceGenerators/XamlGenerationTests.Core/XamlGenerationTests.Core.csproj` pin
`<TargetFramework>$(NetPrevious)</TargetFramework>` (net9.0) directly, but they don't end in
`.Skia.csproj`/`.Wasm.csproj`/`.Reference.csproj`, so `src/targetframework-override.props` force-overrides
them to `UnoTargetFrameworkOverride` (net10.0) whenever it's set — producing
`NETSDK1005: Assets file ... doesn't have a target for 'net9.0'`. Reproduces even after a clean, successful
individual `dotnet restore` of just that project (the conflict only shows up once built as part of the
solution filter with the override active). Pre-existing repo quirk in
`src/targetframework-override.props`'s exemption list, not fixed as part of this work.

### `Uno.UI-RemoteControl-Only.slnf` — 5 known failures

All 7 `*.netcoremobile.csproj` entries in this filter (`Uno.netcoremobile`, `Uno.UI.netcoremobile`,
`Uno.UI.RemoteControl.netcoremobile`, `Uno.UI.Composition.netcoremobile`, `Uno.UI.Toolkit.netcoremobile`,
`Uno.UI.Dispatching.netcoremobile`, `Uno.Foundation.netcoremobile`) fail to compile under a plain `net10.0`
override with `CS0116: A namespace cannot directly contain members such as fields, methods or statements`
in `Uno.UWP/Generated/**` — these projects only make sense built against a real mobile TFM
(`net10.0-android`/`-ios`/`-maccatalyst`), not the generic `net10.0` collapse. This is structural, not a bug:
don't try to build `netcoremobile`-suffixed projects under the Skia/Wasm override at all; they need their own
pass with `UnoTargetFrameworkOverride` set to an actual mobile TFM (and, for Android, a real Android SDK).

## Building on Windows — what it additionally unlocks

The plain-SDK CLI path (`crosstargeting_override.props`, `dotnet restore`/`build` on the Wasm/UnitTests/Skia
filters) is now independently verified on Windows — see "One-time setup" and "Per-`.slnf` results" above.
Everything below this line is still **not** independently tested (no Visual Studio, Android SDK, or
Windows-native/UWP target exercised in that session) — it's transcribed from the repo's own
`doc/articles/uno-development/building-uno-ui.md` plus the CI templates, to fill the gap left by what Linux
structurally can't do. Verify against those files if anything below looks stale.

**Prerequisites** (per the official doc):
- Visual Studio 2026 (18.0+), with workloads:
  - **ASP.NET and Web Development**
  - **.NET Multi-Platform App UI development** (this is what brings in the Android/iOS/maccatalyst/tvOS
    tooling — VS installs its own Android SDK through this, sidestepping the manual `ANDROID_HOME` dance
    that blocked Android on this Linux box)
  - **.NET desktop development**
  - **UWP Development** workload + Windows 10/11 SDK, starting from `10.0.19041` (must match or exceed the
    `TargetPlatformVersion` in `src/Uno.CrossTargetting.targets`) — only needed for the Windows-native target
- Tools ▸ Android ▸ Android SDK Manager: install Android SDKs from 7.1 up (versions listed in
  `src/Uno.UI.BindingHelper.Android/Uno.UI.BindingHelper.Android.netcoremobile.csproj`)
- Run `uno-check` (see above) to set up the .NET Android/iOS workloads
- Latest .NET SDK

**What this unlocks beyond Linux:**
- `Uno.UI-Windows-only.slnf` (`UnoTargetFrameworkOverride=net10.0-windows10.0.19041.0`) — the native
  WinUI/UWP target, impossible on Linux.
- Real Android builds (`Uno.UI-netcoremobile-only.slnf` / `Uno.UI-Skia-only.slnf` with
  `net10.0-android`) without the manual Android SDK install this Linux session was missing — VS's Android
  SDK Manager handles it.
- The full `Uno.UI-packages-windows.slnf` release-package build CI uses (`build/ci/build/.azure-devops-build-managed.yml`),
  which also builds `Uno.WinUI.Graphics3DGL` native Windows binaries (`/p:BuildGraphics3DGLForWindows=true`)
  — this needs the VS **Desktop development with C++** component in addition to the workloads above (not
  listed in the contributor doc, inferred from the CI step needing native C++ compilation).

**Still not fully self-contained even on Windows:**
- iOS/tvOS/macCatalyst: the `.NET MAUI` workload installs on Windows, but actually **compiling** for those
  platforms needs a **paired Mac build host** (standard .NET-for-Apple-platforms requirement, not
  Uno-specific) — Windows alone can restore/edit/IntelliSense those projects but not produce final binaries.
- `Uno.WinAppSDKSyncGenerator` (the WinRT/WinUI API sync tool) **must run on Windows** — it depends on
  Windows SDK WinMD files. Run via a "Developer Command Prompt for Visual Studio", from the `uno\build`
  folder (not `uno\src\build`): `run-api-sync-tool.cmd`. Not run as part of CI; manual/occasional only.

**Windows-specific gotchas called out in the official doc** (not verified here, just transcribed):
- Long-path errors: enable via
  `reg ADD HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1`,
  or suppress the warning with `<UnoUIDisableLongPathWarning>false</UnoUIDisableLongPathWarning>`.
- Changing `UnoTargetFrameworkOverride` while the solution is open in Visual Studio can crash/destabilize VS
  — close the solution first, every time.
- If a rebuild misbehaves: close VS → delete `src/.vs` → rebuild; if that doesn't help, `git clean -fdx`
  (after closing VS).
- Building "all targets at once" (comment out `UnoTargetFrameworkOverride`, open `Uno.UI.slnx` directly) is
  possible but explicitly *not recommended* — much slower/more RAM-intensive than the single-target
  `crosstargeting_override.props` + matching `.slnf` approach documented above (which applies identically on
  Windows).
- Recommended hardware: minimum i7-8th-gen/16GB RAM/250GB fast SSD; optimal i9/32GB/500GB M.2 SSD.

## Runtime (not build) caveat: `Uno.UI.UnitTests` (Linux)

`dotnet test --project Uno.UI.UnitTests/Uno.UI.UnitTests.csproj --no-build` (plain, no explicit RID) builds
fine but 1 of ~139 tests fails at runtime:
```
DllNotFoundException: Unable to load shared library 'libSkiaSharp' ...
```
even though `skiasharp.nativeassets.linux`'s `libSkiaSharp.so` is present in the NuGet cache — it just isn't
copied into the test output dir under a RID-less test run. Not investigated further (135/139 pass); if you
need that last test, try an explicit `-r linux-x64` / `RuntimeIdentifier` on the test project.

## Technique: building a `.slnf` after excluding a few projects, without touching the repo

`.slnf` files are just JSON (`{"solution": {"path": ..., "projects": [...]}}`, UTF-8 **with BOM** — read with
`encoding='utf-8-sig'` in Python or `json.load` will throw). To build a known-good subset without editing a
tracked file:

```python
import json
with open('Uno.UI-Skia-only.slnf', encoding='utf-8-sig') as f:
    d = json.load(f)
d['solution']['projects'] = [p for p in d['solution']['projects'] if 'Lottie.Tests' not in p and ...]
with open('_local-Uno.UI-Skia-only.slnf', 'w', encoding='utf-8-sig') as f:
    json.dump(d, f, indent=2)
```
Put the copy directly in `src/` (next to `Uno.UI.slnx`, since `"path"` inside the filter is relative to it),
build with it, then `rm` it when done — `git status` should come back clean (it's untracked, never add it).

## Quick reference: build commands that worked (Linux)

```
cd src
dotnet restore Uno.UI-Wasm-only.slnf -p:AllowMissingPrunePackageData=true
dotnet build   Uno.UI-Wasm-only.slnf -p:AllowMissingPrunePackageData=true --no-restore -clp:Summary -v:minimal

dotnet restore Uno.UI-UnitTests-only.slnf -p:AllowMissingPrunePackageData=true
dotnet build   Uno.UI-UnitTests-only.slnf -p:AllowMissingPrunePackageData=true --no-restore -clp:Summary -v:minimal
```

## Quick reference: build commands that worked (Windows, SDK `10.0.303`)

No `AllowMissingPrunePackageData` flag needed here — see "One-time setup" above.

```
cd src
dotnet restore Uno.UI-Wasm-only.slnf
dotnet build   Uno.UI-Wasm-only.slnf --no-restore

dotnet restore Uno.UI-UnitTests-only.slnf
dotnet build   Uno.UI-UnitTests-only.slnf --no-restore
```

For `Uno.UI-Skia-only.slnf`, apply the exclusion technique above with the Windows-specific project list from
the "verified exclusion set" subsection (excludes `Lottie.Tests`, `Uno.UI.Runtime.Skia.Android`,
`Uno.UI.Runtime.Skia.AppleUIKit`, `Uno.UI.Runtime.Skia.MacOS`, `SamplesApp.Skia.WebAssembly.Browser`, and
every `*.netcoremobile.csproj` entry — keep the `Win32`/`Win32.Support` entries, they build natively):

```python
import json
with open('Uno.UI-Skia-only.slnf', encoding='utf-8-sig') as f:
    d = json.load(f)
excl = ['Lottie.Tests', '.netcoremobile.csproj', 'Uno.UI.Runtime.Skia.Android.csproj',
        'Uno.UI.Runtime.Skia.AppleUIKit', 'Uno.UI.Runtime.Skia.MacOS', 'SamplesApp.Skia.WebAssembly.Browser']
d['solution']['projects'] = [p for p in d['solution']['projects'] if not any(x in p for x in excl)]
with open('_local-Uno.UI-Skia-only.slnf', 'w', encoding='utf-8-sig') as f:
    json.dump(d, f, indent=2)
```
```
dotnet restore _local-Uno.UI-Skia-only.slnf
dotnet build   _local-Uno.UI-Skia-only.slnf --no-restore
```

**Side effect to watch for**: a Skia build regenerates `Uno.UI.FluentTheme.v2/themeresources_v2.xaml` as
part of "Generating theme resources XAML file", which shows up as a tracked-file diff afterward even though
you didn't edit it. `git checkout -- src/Uno.UI.FluentTheme.v2/themeresources_v2.xaml` to discard it before
committing anything else.

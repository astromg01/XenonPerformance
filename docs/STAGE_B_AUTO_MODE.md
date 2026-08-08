# Stage B1 Auto Mode and Identity Collector

## Goal

Stage B1 supplies the always-on decision layer for Xenon Performance and the
read-only game identity collector needed to build the first exact profile. It
does not claim a performance gain. It makes a later optimization eligible only
when the running Xbox 360 executable is identified exactly and a paired
rollback handler exists.

## Aurora freeze correction

The first Stage B artifact used the PE/XEX base address `0x82000000`. That range
is normal title executable space and can collide with Aurora or a game. Stage B1
uses the conventional system-plugin base `0x91D00000`, with code beginning at
`0x91D10000`.

The worker also avoids loader races:

1. wait 10 seconds after DLL attach;
2. poll only every 5 seconds;
3. skip zero and reserved `FFxxxxxx` dashboard/homebrew Title IDs;
4. require the same Title ID and loader-module pointer twice;
5. validate mapped ranges with `MmIsAddressValid`;
6. read execution metadata through `RtlImageXexHeaderField`;
7. confirm Title ID and module pointer again after capture.

## Identity contract

After the initial delay, the resident worker polls `XamGetCurrentTitleId` every
5,000 ms. Once a game is stable for two samples, it reads the current XEX
metadata already mapped by the loader. A profile key contains:

1. Title ID
2. Media ID
3. Version
4. Base Version
5. 20-byte authenticated XEX header digest

The Title ID returned by XAM must equal the Title ID in the execution-info
header. Invalid addresses, malformed headers, inconsistent IDs, module changes,
unknown builds and an empty registry all resolve to `NO-OP`.

## Collector output

The first stable game identity is formatted as plain ASCII and synchronously
written once for that exact identity transition. The primary path is:

```text
Usb0:\XenonPerformanceIdentity.txt
```

If that alias cannot be opened, the worker tries:

```text
Usb:\XenonPerformanceIdentity.txt
```

The report contains `TITLE_ID`, `MEDIA_ID`, `VERSION`, `BASE_VERSION` and the
40-character authenticated `HEADER_DIGEST`. No game memory is changed.

## State flow

`disabled -> no-title -> unknown-title-noop -> matched-dry-run -> active`

An identity change reverts the active profile before another lookup. An apply
failure leaves the runtime inactive. The portable state-machine tests cover
exact matching, version and digest mismatches, dry-run, arming, apply failure,
idempotence and rollback.

## Safety contract

Stage B has the following non-negotiable gates:

- no universal or guessed game patch;
- no NAND, flash, SMC, fan, clock or voltage changes;
- no `.loaded` marker, notification or heap allocation;
- filesystem access is limited to the deterministic identity report above;
- no handler call for unknown identities;
- no profile without an exact key and a revert handler;
- no future write unless expected original bytes are validated first.

The compile-time resident registry currently has `profile_count=0`. Therefore
Stage B1 collects identities but cannot modify a game.

## Physical Xbox 360 boundary

The GitHub build proves source gates, ABI shape, high plugin load address, XEX
container structure and the zero-game-write policy. Only a physical RGH/JTAG
Xbox 360 can prove that the DashLaunch resident thread survives title
transitions. The console path remains:

```text
Usb0:\XenonPerformancePlugin.xex
```

with DashLaunch:

```ini
plugin1 = Usb:\XenonPerformancePlugin.xex
```

This build deliberately has no visual notification and creates no `.loaded`
file. A successful test means Aurora completes loading, a game remains stable,
and `XenonPerformanceIdentity.txt` appears after roughly 15 seconds. The
following milestone must add one title-specific, dry-run-only profile using
that collected evidence.

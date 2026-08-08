# Stage B Auto Mode

## Goal

Stage B supplies the always-on decision layer for Xenon Performance. It does
not claim a performance gain. It makes a later optimization eligible only when
the running Xbox 360 executable is identified exactly and a paired rollback
handler exists.

## Identity contract

The resident worker polls `XamGetCurrentTitleId` every 2,000 ms and reads the
current XEX metadata already mapped by the loader. A profile key contains:

1. Title ID
2. Media ID
3. Version
4. Base Version
5. 20-byte authenticated XEX header digest

The Title ID returned by XAM must equal the Title ID in the execution-info
header. Invalid pointers, malformed headers, inconsistent IDs, unknown builds
and an empty registry all resolve to `NO-OP`.

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
- no filesystem marker, log, notification or heap allocation;
- no handler call for unknown identities;
- no profile without an exact key and a revert handler;
- no future write unless expected original bytes are validated first.

The compile-time resident registry currently has `profile_count=0`. Therefore
the first Stage B XEX observes title transitions but cannot modify a game.

## Physical Xbox 360 boundary

The GitHub build proves source gates, ABI shape, XEX container structure and
the no-write policy. Only a physical RGH/JTAG Xbox 360 can prove that the
DashLaunch resident thread survives title transitions. The console path remains:

```text
Usb0:\XenonPerformancePlugin.xex
```

with DashLaunch:

```ini
plugin1 = Usb:\XenonPerformancePlugin.xex
```

This build deliberately has no visual notification and creates no `.loaded`
file. The following milestone must add one title-specific, dry-run-only profile
using evidence collected for that exact game build.

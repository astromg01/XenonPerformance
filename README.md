# Xenon Performance

Xbox 360 homebrew diagnostics and conservative, title-specific performance
research.

## Current milestone: Stage B1 Stable Collector

The Stage B runtime establishes the safe control plane for future game
profiles:

- loads at the system-plugin base `0x91D00000`, away from normal title space;
- waits 10 seconds, then polls `XamGetCurrentTitleId` every five seconds;
- ignores dashboard/homebrew Title IDs and requires two stable samples;
- identifies an execution by Title ID, Media ID, Version, Base Version and the
  authenticated XEX header digest;
- writes that exact identity to `Usb0:\XenonPerformanceIdentity.txt`;
- accepts only an exact compile-time registry match;
- reverts an active profile before a title transition;
- treats missing, invalid and unknown identities as a mandatory no-op.

The shipped Stage B1 registry is intentionally empty. It performs **zero game,
kernel, NAND, SMC or clock writes and provides no FPS gain yet**. Its only
filesystem write is the identity report needed for the next profile. Its
purpose is to make that title-specific profile deterministic and reversible
instead of relying on guessed offsets.

See [`docs/STAGE_B_AUTO_MODE.md`](docs/STAGE_B_AUTO_MODE.md) for the state
machine, safety contract and hardware test boundary.

## Validation

The host model and resident POWERPCBE XEX are validated independently:

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror -pedantic \
  src/xp_auto_mode.c tests/test_auto_mode.c -o xp_auto_mode_tests
./xp_auto_mode_tests
```

GitHub Actions also assembles the resident DLL, verifies its embedded
POWERPCBE PE, packages it through SynthXEX and publishes a diagnostic bundle.

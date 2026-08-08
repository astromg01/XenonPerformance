# Xenon Performance

Xbox 360 homebrew diagnostics and conservative, title-specific performance
research.

## Current milestone: Stage B Auto Mode

The Stage B runtime establishes the safe control plane for future game
profiles:

- polls `XamGetCurrentTitleId` every two seconds;
- identifies an execution by Title ID, Media ID, Version, Base Version and the
  authenticated XEX header digest;
- accepts only an exact compile-time registry match;
- reverts an active profile before a title transition;
- treats missing, invalid and unknown identities as a mandatory no-op.

The shipped Stage B registry is intentionally empty. It performs **zero game,
kernel, NAND, SMC, clock or filesystem writes and provides no FPS gain yet**.
Its purpose is to make the next title-specific profile deterministic and
reversible instead of relying on guessed offsets.

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

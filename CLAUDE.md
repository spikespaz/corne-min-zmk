# corne-min ZMK

Split ergonomic keyboard (MoErgo corne-min hardware, MechboardsLTD firmware modules).
Uses a Prospector dongle (seeeduino_xiao_ble) as the central BLE host.

## Build

Nix flake at repo root (`flake.nix`). Requires NixOS/WSL with flakes enabled.

```sh
nix build .#left     # left half + ZMK Studio
nix build .#right    # right half
nix build .#dongle   # Prospector dongle
nix build .#reset    # BLE pairing reset UF2
nix run   .#update   # refresh zephyrDepsHash after ZMK version bump
```

**Flake structure:** `zmk-nix.overlays.default` is applied to `pkgsFor` so `buildKeyboard`
lives directly in the package set. `flash`/`update`/`devShell` via
`pkgs.callPackage "${zmk-nix}/nix/..."` to avoid a second nixpkgs evaluation.
Systems: `aarch64-linux` and `x86_64-linux` only (WSL/Linux targets).

**First build bootstrap:** `zephyrDepsHash = lib.fakeHash` in `flake.nix`.
Run `nix build .#left`, copy the `got: sha256-...` from the error, replace `lib.fakeHash`, run again.

CI also builds on push via `.github/workflows/build.yml` → `zmkfirmware/zmk/.github/workflows/build-user-config.yml@v0.3`.

## Branches and PRs

Branch naming: `u/<handle>/<objective>` for human branches, `b/<agent>/<objective>` for bot branches.

Once a PR is open, repurpose it rather than closing and reopening. Don't worry about fixing branch names.

## Keymap

`config/corne_min.keymap` — Colemak-DH with Glorious Engrammer-style homerow mods.

### Homerow mod behaviors

Sunaku level-0 timings (TAPPING_RESOLUTION=150ms) with bilateral enforcement.

```
HRM_L(label, name, tt)  — left hand, fires on right-hand key release
HRM_R(label, name, tt)  — right hand, fires on left-hand key release
```

GACS outer→inner: pinky=GUI, ring=ALT, middle=CTL, index=SFT.
Timing offsets (index+30, middle+60, ring+90, pinky+120):

| Behavior | Finger | Mod  | ms  | Key |
|----------|--------|------|-----|-----|
| `lhp`    | pinky  | LGUI | 270 | A   |
| `lhr`    | ring   | LALT | 240 | R   |
| `lhm`    | middle | LCTL | 210 | S   |
| `lhi`    | index  | LSFT | 180 | T   |
| `rhi`    | index  | RSFT | 180 | N   |
| `rhm`    | middle | RCTL | 210 | E   |
| `rhr`    | ring   | RALT | 240 | I   |
| `rhp`    | pinky  | RGUI | 270 | O   |

Shared params: `flavor=balanced`, `quick-tap-ms=300`, `require-prior-idle-ms=150`, `hold-trigger-on-release`.
Key positions: `KEYS_L`/`KEYS_R` defined from the standard 42-key Corne matrix transform.

### Pending tuning

- After testing feel: may want to adjust `require-prior-idle-ms` per-finger (add 4th macro param `idle` to `HRM_L`/`HRM_R`).

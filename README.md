# pod_ble

BLE link between the weight-bearing monitor pod (**nRF54L15**, firmware in **Rust**) and the **Flutter** mobile app.

```
pod_ble/
├── protocol/GATT.md           the pod <-> app contract (UUIDs, byte layouts, flow, golden vectors)
├── firmware/
│   ├── pod-protocol/          no_std Rust crate: byte layouts; tests run on any laptop
│   └── pod-ble/               Embassy firmware for the nRF54L15: BLE peripheral + Step Record Service
└── mobile/
    └── pod_ble_client/        Flutter package the app uses to talk to a pod (+ example bench app)
```

## Firmware stack

| Layer | Crate | Notes |
|---|---|---|
| Async runtime + HAL | [Embassy](https://embassy.dev) (`embassy-nrf`) | nRF54L15 application core, secure mode |
| BLE controller (link layer) | [`nrf-sdc`](https://github.com/alexmoon/nrf-sdc) | Rust wrapper around Nordic's own SoftDevice Controller + MPSL binaries |
| BLE host (GAP/GATT) | [TrouBLE](https://github.com/embassy-rs/trouble) (`trouble-host`) | Embassy project's async host stack |
| Protocol | `pod-protocol` (this repo) | Shared byte layouts, unit-tested |

Versions are pinned in `firmware/pod-ble/Cargo.toml` to the git revisions used by TrouBLE's own nRF54 example. That example is built in upstream CI. nRF54L15 support in these crates is newer than their crates.io releases, so pinning by git revision is deliberate. Upgrade them together.

### One-time setup (Windows, macOS or Linux)

1. **Rust:** install [rustup](https://rustup.rs). The pinned toolchain (1.97) and the `thumbv8m.main-none-eabihf` target install automatically from `rust-toolchain.toml` the first time you build.
2. **probe-rs** (flashing and logs over the DK's on-board debugger):
   ```bash
   cargo install cargo-binstall
   cargo binstall probe-rs-tools
   ```
   On Windows, if the DK isn't detected, install the [SEGGER J-Link drivers](https://www.segger.com/downloads/jlink/). On Linux, add the [probe-rs udev rules](https://probe.rs/docs/getting-started/probe-setup/).
3. **LLVM/clang** (`nrf-sdc` generates bindings to Nordic's C headers at build time):
   - Windows: `winget install LLVM.LLVM`, then set `LIBCLANG_PATH=C:\Program Files\LLVM\bin` if the build can't find it
   - macOS: `brew install llvm`
   - Linux: `sudo apt install clang`

### Build, flash, view logs (nRF54L15 DK)

```bash
cd firmware/pod-ble
cargo run --release
```

`cargo run` builds, flashes through probe-rs, and streams defmt logs. Look for `[adv] advertising as "WB-Pod"`. To build without flashing, run `cargo build --release`.

By default the firmware generates a fake step every second (`simulate-steps` feature). To build without it: `cargo run --release --no-default-features`.

### Protocol tests (no hardware needed)

```bash
cd firmware/pod-protocol
cargo test
```

### Custom pod PCB

When the pod board exists, check the clock config in `src/main.rs`. The DK has a 32.768 kHz crystal; if the pod doesn't, switch the LF clock to the RC oscillator. Also check the flash and RAM sizes in `memory.x`.

## Mobile

See [`mobile/README.md`](mobile/README.md). The short version: the app depends on `mobile/pod_ble_client`, and `example/` is a bench app for testing the link from a phone. To test before the app exists, use Nordic's **nRF Connect for Mobile**: scan for `WB-Pod`, connect, and enable notifications on `fbe30002-…`.

## Ownership

- `firmware/`: the BLE layer here feeds into Vineet's pod firmware pipeline. Coordinate with him before changing anything outside the Step Record Service.
- `protocol/`: Communication team (OJ, Fares, Jacob). Changes need sign-off from both the firmware and the app side.
- `mobile/`: Communication and Platforms.

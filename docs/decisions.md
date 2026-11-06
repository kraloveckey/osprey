# Architecture Decision Records (ADR)

Author: kraloveckey  
Date: 2026-10-25  
Status: Approved  

---

## ADR-001: Standalone Single-Binary Architecture in Rust

### Context
Diagnostics tools for storage and hardware health on macOS and Linux often rely on fragmented utilities. GSmartControl requires legacy desktop toolkits, while traditional tools are often restricted to other platforms. Users need a high-performance, single-executable diagnostic tool that provides both a command-line interface (CLI) for shell workflows and a lightweight desktop widget for continuous health awareness.

### Decision
Implement Osprey entirely in Rust, utilizing a decoupled modular architecture:
1. Low-level telemetry collectors (`engine::macos`, `engine::linux`, `engine::battery`, `engine::smartctl`).
2. Central domain structures (`models::disk`, `models::smart`, `models::battery`, `models::system`).
3. Embedded presentation layer compiled directly into the binary via `include_str!`, eliminating external asset dependencies.
4. Lightweight asynchronous server engine powered by Tokio and Axum.

### Consequences
- Zero runtime runtime dependencies or external framework installations.
- Cross-platform portability across macOS (ARM64 and Intel) and Linux.
- Predictable memory footprint (< 25 MB RAM during active telemetry polling).

---

## ADR-002: Dual-Engine Drive and S.M.A.R.T. Inspection Strategy

### Context
Apple Silicon Macs utilize proprietary controller protocols (Apple Fabric / ANS) for internal NVMe flash storage, alongside standard USB and Thunderbolt attached external enclosures. Querying physical disk health requires combining block device topology with low-level NVMe log page inspection.

### Decision
Adopt a resilient dual-engine inspection pipeline:
1. **Topology Discovery**: Utilize native platform parsers (`diskutil` and `system_profiler SPStorageDataType` on macOS, `/sys/block` and `lsblk` on Linux) to map physical disks, partition schemes, volume names, and mount points.
2. **S.M.A.R.T. Protocol Telemetry**: Interface with `smartctl` in JSON mode (`-j -a`) to extract NVMe Log Page 0x02 attributes, wear levels, spare capacity thresholds, and error logs, with automatic fallbacks for ATA/SATA enclosures.

### Consequences
- Uncompromised accuracy for Apple Silicon internal NVMe storage.
- Seamless support for external enclosures (SATA, NVMe via USB-C, Thunderbolt).
- Graceful degradation if raw telemetry permissions are restricted.

---

## ADR-003: Integrated Battery Health and Degradation Tracking

### Context
Modern portable workstations experience storage endurance degradation concurrently with chemical battery cell wear. Providing storage diagnostics alongside battery cycle telemetry provides complete hardware health awareness in a unified view.

### Decision
Incorporate first-class battery telemetry into the core domain:
- On macOS: Parse `ioreg -rn AppleSmartBattery` to decode raw cycle counts, factory design capacity, maximum charge capacity, voltage, and charger wattage.
- On Linux: Inspect `/sys/class/power_supply/` sysfs trees (`energy_full`, `energy_full_design`, `cycle_count`, `voltage_now`).

### Consequences
- Complete hardware vitals available in a single unified dashboard and terminal report.
- Accurate cell degradation percentage calculations based on factory specifications.

---

## ADR-004: Native macOS Desktop HUD & Telemetry Layout

### Context
Hardware monitoring tools frequently suffer from cluttered, utilitarian interfaces. The desktop interface requires modern visual polish conforming to Apple human interface standards, with dynamic sizing and tactile micro-interactions.

### Decision
Implement a floating desktop HUD inspired by compact widget ergonomics and Emil Kowalski Apple design principles:
- Frosted glass translucent background (`backdrop-filter: blur(30px) saturate(190%)`).
- Tri-state size switcher (`S`, `M`, `L`):
  - `S`: Compact essential HUD (Disk and Battery summary bars).
  - `M`: Standard balanced view (Disk, Power, CPU load, Memory).
  - `L`: Deep inspection view with complete S.M.A.R.T. attributes table.
- Interactive hexadecimal and decimal raw value toggles for hardware engineers.

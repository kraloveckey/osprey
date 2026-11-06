# Trust Boundary & Threat Model

Author: kraloveckey  
Status: Verified Security Specification  

---

## 1. Security Architecture & Principles

Osprey is engineered as a local diagnostic telemetry tool designed with strict read-only execution constraints. The software operates entirely offline without telemetry beacons, tracking, or remote network dependencies.

```
+-----------------------------------------------------------------------+
|                             USER REALM                                |
|   Terminal CLI  |  Desktop Widget (S/M/L)  |  Prometheus Scraper      |
+-----------------------------------------------------------------------+
                                   | (Local Loopback HTTP / IPC)
                                   v
+-----------------------------------------------------------------------+
|                          OSPREY CORE ENGINE                           |
|   - Axum Loopback Listener (127.0.0.1)                                |
|   - Read-Only Command Dispatcher                                      |
|   - Sanitized Process Argument Invocation                             |
+-----------------------------------------------------------------------+
                                   |
                  +----------------+----------------+
                  |                                 |
                  v                                 v
        +-------------------+             +-------------------+
        |  Storage Devices  |             | Battery / Sensors |
        |  (NVMe / SATA)    |             | (ioreg / sysfs)   |
        |  READ-ONLY S.M.A.R.T. |         | READ-ONLY QUERY   |
        +-------------------+             +-------------------+
```

---

## 2. Threat Vector Mitigations

### 2.1 Read-Only Disk Access Guarantee
- **Invariant**: Osprey strictly issues non-destructive informational queries (`-j -a`, `diskutil info`, `diskutil list`, `sysinfo`).
- **Mitigation**: Under zero circumstances does Osprey invoke destructive formatting, partition table modifications, or NVMe format namespace commands (`nvme format`, `diskutil eraseDisk`).

### 2.2 Shell Injection Prevention
- **Invariant**: Diagnostic system commands are never passed through a shell interpreter (`/bin/sh -c` or `bash -c`).
- **Mitigation**: All platform subcommands are executed using direct binary paths (`/usr/sbin/diskutil`, `/opt/homebrew/bin/smartctl`) with typed, vector-passed arguments via Rust standard library `Command::args(&[...])`.

### 2.3 Network Sandboxing
- **Invariant**: The embedded widget server binds exclusively to the local loopback interface (`127.0.0.1`).
- **Mitigation**: Incoming connections from external network interfaces (`0.0.0.0` or WAN IPs) are rejected by default unless explicitly configured via the `--host` flag by an administrator.

### 2.4 Local Privacy & Memory Safety
- Written in safe Rust with Link-Time Optimization (LTO) and zero raw pointer dereferences in user-facing code paths.
- Zero collection or transmission of personal device identifiers, user names, or file contents. Telemetry is confined strictly to hardware counters (cycles, temperatures, byte volumes, and capacity values).

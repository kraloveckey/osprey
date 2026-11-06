# Osprey Telemetry Protocol & Wire Specification

Author: kraloveckey  
Specification Version: 1.0.0  

---

## 1. Overview & Transport Protocol

Osprey delivers real-time hardware telemetry across three interaction channels:
1. **Command-Line Interface (CLI)**: Formatted ANSI stream with styled tables and S.M.A.R.T. diagnostics export.
2. **REST API**: Structured JSON payloads served over local HTTP.
3. **Prometheus Metrics**: Time-series counters and gauges formatted for telemetry ingestion.

---

## 2. REST Endpoints Specification

### 2.1 Disk Telemetry (`GET /api/drives`)

Returns an array of physical disk objects detected on the host system.

```json
[
  {
    "id": "disk0",
    "device_node": "/dev/disk0",
    "model_name": "APPLE SSD AP1024Z",
    "serial_number": "0333a0883439a02e",
    "firmware_revision": "241.0.12",
    "protocol": "Apple Fabric",
    "media_type": "SSD",
    "size_bytes": 1000555581440,
    "size_formatted": "931.8 GB",
    "is_internal": true,
    "is_removable": false,
    "partitions": [
      {
        "id": "disk3s5",
        "name": "Data",
        "size_bytes": 926300000000,
        "size_formatted": "926.3 GB",
        "mount_point": "/System/Volumes/Data",
        "file_system": "APFS",
        "is_boot_volume": false
      },
      {
        "id": "disk3s1s1",
        "name": "Macintosh HD",
        "size_bytes": 926300000000,
        "size_formatted": "926.3 GB",
        "mount_point": "/",
        "file_system": "APFS",
        "is_boot_volume": true
      }
    ],
    "smart": {
      "health_status": "GOOD",
      "health_percent": 100,
      "temperature_celsius": 32,
      "temperature_fahrenheit": 89,
      "power_on_hours": 334,
      "power_cycles": 137,
      "unsafe_shutdowns": 5,
      "data_units_read_bytes": 22312678656000,
      "data_units_read_formatted": "20.3 TB",
      "data_units_written_bytes": 10332890624000,
      "data_units_written_formatted": "9.4 TB",
      "host_read_commands": 929532808,
      "host_write_commands": 358177582,
      "percentage_used": 0,
      "available_spare": 100,
      "available_spare_threshold": 99,
      "critical_warning": 0,
      "media_errors": 0,
      "error_entries_count": 0,
      "attributes": [
        {
          "id": 1,
          "name": "Critical Warning",
          "current": 100,
          "worst": 100,
          "threshold": 0,
          "raw_value": 0,
          "raw_hex": "0x000000000000",
          "status": "normal"
        }
      ],
      "supported_features": ["S.M.A.R.T.", "TRIM", "VolatileWriteCache"]
    }
  }
]
```

---

### 2.2 Battery Telemetry (`GET /api/battery`)

Returns host battery cell degradation, cycle counts, pack voltage, and charger telemetry.

```json
{
  "installed": true,
  "health_status": "Good",
  "health_percent": 100.3,
  "cycle_count": 8,
  "design_cycle_count": 1000,
  "current_capacity_percent": 80,
  "full_charge_capacity_mah": 4644,
  "design_capacity_mah": 4629,
  "nominal_charge_capacity_mah": 4771,
  "remaining_capacity_mah": 3678,
  "voltage_mv": 12569,
  "amperage_ma": 0,
  "is_charging": false,
  "is_fully_charged": false,
  "external_connected": true,
  "power_adapter_watts": 60,
  "device_name": "bq40z651",
  "serial_number": "BAT-MOCK-SERIAL-01"
}
```

---

### 2.3 System Vitals (`GET /api/system`)

Provides host vitals for the desktop widget header and KPI indicators.

```json
{
  "os_name": "Darwin",
  "os_version": "27.0.1",
  "host_name": "edge-node-01",
  "chip_name": "Apple Silicon",
  "uptime_formatted": "6d 15h",
  "cpu_usage_percent": 21.0,
  "memory_total_bytes": 25769803776,
  "memory_used_bytes": 20018741248,
  "memory_free_bytes": 5751062528,
  "memory_total_formatted": "24.0 GB",
  "memory_used_formatted": "18.6 GB",
  "memory_free_formatted": "5.4 GB",
  "memory_used_percent": 77.6
}
```

---

## 3. S.M.A.R.T. NVMe Log Page 0x02 Decoding Specification

For NVMe solid state drives, Osprey queries log page 0x02 (`SMART / Health Information`) as defined in the NVM Express Base Specification:

| Byte Offset | Attribute Description | Unit / Scaling |
|-------------|-----------------------|----------------|
| 0 | Critical Warning | Bitmask (0x00 = OK) |
| 1:2 | Composite Temperature | Kelvin (converted to °C and °F) |
| 3 | Available Spare | Percentage (0–100%) |
| 4 | Available Spare Threshold | Normalized threshold percentage |
| 5 | Percentage Used | Endurance consumption estimate (0–255%) |
| 32:47 | Data Units Read | Units of 512,000 bytes (scaled to TB) |
| 48:63 | Data Units Written | Units of 512,000 bytes (scaled to TBW) |
| 64:79 | Host Read Commands | Raw 128-bit counter |
| 80:95 | Host Write Commands | Raw 128-bit counter |
| 112:127 | Power Cycles | Raw 128-bit integer |
| 128:143 | Power On Hours | Hours count |
| 144:159 | Unsafe Shutdowns | Counter |
| 160:175 | Media and Data Integrity Errors | Raw counter (Unrecoverable media errors) |
| 176:191 | Error Information Log Entries | Total entries count |

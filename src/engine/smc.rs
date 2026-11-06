//! CPU temperature from the AppleSMC (macOS), the same source the native app
//! uses (`macos/Sources/OspreyCore/Power/SMCTemperature.swift`).
//!
//! Apple Silicon: every `Tp…` key of type `flt ` is a CPU-cluster sensor; the
//! key names change per chip generation, so the key list is scanned once and
//! the median of the plausible readings is reported.
//! Intel: the classic `TC0P`/`TC0D`/`TC0E`/`TC0F` keys (`sp78` fixed point).
//!
//! A read-only AppleSMC connection needs neither root nor entitlements.

use std::ffi::{c_char, c_void};
use std::sync::Mutex;

type KernReturn = i32;
type MachPort = u32;
type IoObject = u32;
type IoConnect = u32;

#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOServiceMatching(name: *const c_char) -> *mut c_void;
    fn IOServiceGetMatchingService(main_port: MachPort, matching: *mut c_void) -> IoObject;
    fn IOServiceOpen(service: IoObject, owning_task: MachPort, kind: u32, connect: *mut IoConnect) -> KernReturn;
    fn IOObjectRelease(object: IoObject) -> KernReturn;
    fn IOConnectCallStructMethod(
        connection: IoConnect,
        selector: u32,
        input: *const c_void,
        input_size: usize,
        output: *mut c_void,
        output_size: *mut usize,
    ) -> KernReturn;
}

extern "C" {
    static mach_task_self_: MachPort;
}

const KERNEL_INDEX_SMC: u32 = 2;
const CMD_READ_BYTES: u8 = 5;
const CMD_READ_INDEX: u8 = 8;
const CMD_READ_KEYINFO: u8 = 9;

// Must match the kernel's SMCParamStruct layout exactly (80 bytes).
#[repr(C)]
#[derive(Default, Clone, Copy)]
struct SmcVersion {
    major: u8,
    minor: u8,
    build: u8,
    reserved: u8,
    release: u16,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct SmcPLimitData {
    version: u16,
    length: u16,
    cpu_p_limit: u32,
    gpu_p_limit: u32,
    mem_p_limit: u32,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct SmcKeyInfo {
    data_size: u32,
    data_type: u32,
    data_attributes: u8,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct SmcParam {
    key: u32,
    vers: SmcVersion,
    p_limit_data: SmcPLimitData,
    key_info: SmcKeyInfo,
    result: u8,
    status: u8,
    data8: u8,
    data32: u32,
    bytes: [u8; 32],
}

const _: () = assert!(std::mem::size_of::<SmcParam>() == 80);

const fn four_cc(s: &[u8; 4]) -> u32 {
    ((s[0] as u32) << 24) | ((s[1] as u32) << 16) | ((s[2] as u32) << 8) | (s[3] as u32)
}

struct Smc {
    connection: IoConnect,
    cpu_keys: Option<Vec<(u32, u32)>>, // (key, data type), cached after the first scan
}

impl Smc {
    fn open() -> Option<Smc> {
        unsafe {
            let matching = IOServiceMatching(c"AppleSMC".as_ptr());
            // MACH_PORT_NULL == kIOMainPortDefault
            let service = IOServiceGetMatchingService(0, matching);
            if service == 0 {
                return None;
            }
            let mut connection: IoConnect = 0;
            let kr = IOServiceOpen(service, mach_task_self_, 0, &mut connection);
            IOObjectRelease(service);
            (kr == 0 && connection != 0).then_some(Smc { connection, cpu_keys: None })
        }
    }

    fn call(&self, input: &SmcParam) -> Option<SmcParam> {
        let mut output = SmcParam::default();
        let mut out_size = std::mem::size_of::<SmcParam>();
        let kr = unsafe {
            IOConnectCallStructMethod(
                self.connection,
                KERNEL_INDEX_SMC,
                input as *const SmcParam as *const c_void,
                std::mem::size_of::<SmcParam>(),
                &mut output as *mut SmcParam as *mut c_void,
                &mut out_size,
            )
        };
        (kr == 0 && output.result == 0).then_some(output)
    }

    fn key_info(&self, key: u32) -> Option<SmcKeyInfo> {
        let input = SmcParam { key, data8: CMD_READ_KEYINFO, ..Default::default() };
        self.call(&input).map(|o| o.key_info)
    }

    fn read_bytes(&self, key: u32, info: SmcKeyInfo) -> Option<[u8; 32]> {
        let input = SmcParam { key, key_info: info, data8: CMD_READ_BYTES, ..Default::default() };
        self.call(&input).map(|o| o.bytes)
    }

    fn key_count(&self) -> u32 {
        let key = four_cc(b"#KEY");
        self.key_info(key)
            .and_then(|info| self.read_bytes(key, info))
            .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
            .unwrap_or(0)
    }

    fn key_at(&self, index: u32) -> Option<u32> {
        let input = SmcParam { data8: CMD_READ_INDEX, data32: index, ..Default::default() };
        self.call(&input).map(|o| o.key)
    }

    /// Temperature in °C for `flt ` (little-endian f32) and `sp78` keys.
    fn read_temp(&self, key: u32) -> Option<f32> {
        let info = self.key_info(key)?;
        let bytes = self.read_bytes(key, info)?;
        let value = if info.data_type == four_cc(b"flt ") && info.data_size == 4 {
            f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
        } else if info.data_type == four_cc(b"sp78") && info.data_size == 2 {
            i16::from_be_bytes([bytes[0], bytes[1]]) as f32 / 256.0
        } else {
            return None;
        };
        (value > 0.0 && value < 130.0).then_some(value)
    }

    fn discover_cpu_keys(&self) -> Vec<(u32, u32)> {
        // Apple Silicon: scan for Tp… float sensors.
        let mut keys: Vec<(u32, u32)> = (0..self.key_count())
            .filter_map(|i| self.key_at(i))
            .filter(|k| (k >> 16) == ((b'T' as u32) << 8 | b'p' as u32))
            .filter_map(|k| self.key_info(k).map(|info| (k, info.data_type)))
            .filter(|(k, t)| *t == four_cc(b"flt ") && self.read_temp(*k).is_some())
            .collect();
        if keys.is_empty() {
            // Intel Macs.
            keys = [b"TC0P", b"TC0D", b"TC0E", b"TC0F"]
                .iter()
                .map(|k| four_cc(k))
                .filter(|k| self.read_temp(*k).is_some())
                .map(|k| (k, 0))
                .collect();
        }
        keys
    }

    fn cpu_temperature(&mut self) -> Option<f32> {
        if self.cpu_keys.is_none() {
            self.cpu_keys = Some(self.discover_cpu_keys());
        }
        let keys = self.cpu_keys.as_ref()?;
        let mut values: Vec<f32> = keys.iter().filter_map(|(k, _)| self.read_temp(*k)).collect();
        median(&mut values)
    }
}

/// Median of the readings; `None` when empty or implausibly hot (a broken
/// sensor set), mirroring `SMCTemperature.aggregate` in the app.
pub fn median(values: &mut [f32]) -> Option<f32> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mid = values.len() / 2;
    let m = if values.len() % 2 == 0 { (values[mid - 1] + values[mid]) / 2.0 } else { values[mid] };
    (m <= 110.0).then_some(m)
}

// The connection stays open for the life of the process (`osprey top`,
// widget server) so the key scan runs only once.
struct SmcHandle(Option<Smc>);
// SAFETY: an io_connect_t is a plain Mach port name; access is serialised by the Mutex.
unsafe impl Send for SmcHandle {}

static SMC: Mutex<Option<SmcHandle>> = Mutex::new(None);

pub fn cpu_temperature() -> Option<f32> {
    let mut guard = SMC.lock().unwrap_or_else(|e| e.into_inner());
    let handle = guard.get_or_insert_with(|| SmcHandle(Smc::open()));
    handle.0.as_mut()?.cpu_temperature()
}

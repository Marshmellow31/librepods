# LibrePods Windows Port Plan

## 1. Repository Analysis & Architectural Comparison

This plan outlines the architecture for porting **LibrePods** to Windows as an official fork, reusing vetted code from three reference repositories while preserving upstream GPLv3 compatibility and attribution.

### Reference Repositories Analyzed

| Repository | Stack | Role & Architectural Assessment | License |
|---|---|---|---|
| **librepods-org/librepods** (Primary) | C++ / Qt 6 / CMake | Official upstream. Defines core AAP protocol structures, packet formats, battery & ear detection models, and QML tray UI. Targets Linux (BlueZ / D-Bus / PulseAudio) and Android. | GPLv3 |
| **Tblob18/librepods-windows** | C++ / Qt 6 / CMake | Fork adding a `windows/` tree. Replaces PulseAudio with Windows Core Audio (WASAPI), D-Bus sleep monitoring with Win32 power broadcast messages, and autostart with Windows Registry. Stubs D-Bus Bluetooth monitoring. Attempted L2CAP via Qt Bluetooth socket (which fails on Windows). | GPLv3 |
| **will-ch-h/librepods-windowsbridge** | C++ / Qt 6 / CMake | Fork of Tblob18. Successfully implements working AirPods AACP control over L2CAP on Windows by introducing `WinL2capSocket` interfacing with a KMDF Bluetooth profile driver (`l2cap-windowsdriver`, derived from Microsoft's `bthecho` sample). | GPLv3 |
| **ivLis-Studio/librepods-windows** | C# / WPF / .NET 8 + KMDF C driver | Full rewrite in C# with a native bridge DLL and custom KMDF BTHENUM driver. Proves driver-backed IOCTL communication (`LIBREPODS_IOCTL_OPEN_AACP_CHANNEL`, etc.) and Windows WinRT BLE advertisement scanning, but departs from the official Qt/C++ codebase. | GPLv3 |

---

## 2. Component Reuse Matrix

### What Can Be Reused Directly

| Component | Source Repository | Rationale & Path |
|---|---|---|
| **Core Protocol Definitions** | `librepods-org/librepods` (`linux/`) | `airpods_packets.h`, `BasicControlCommand.hpp`, `enums.h`, `battery.hpp`, `deviceinfo.hpp`, `eardetection.hpp`. These are platform-agnostic packet builders and state models. |
| **Windows Audio Controller (WASAPI)** | `Tblob18/librepods-windows` (`windows/media/`) | `windowsaudiocontroller.cpp/h` uses `IMMDeviceEnumerator` and `IAudioEndpointVolume` to manage Windows master and device volume cleanly without PulseAudio. |
| **Windows Sleep & Power Monitor** | `Tblob18/librepods-windows` (`windows/`) | `windowssleepmonitor.cpp/hpp` uses Win32 message-only window and `RegisterSuspendResumeNotification` / `WM_POWERBROADCAST` to handle sleep/wake state transitions. |
| **Windows Registry Autostart** | `Tblob18/librepods-windows` (`windows/`) | `autostartmanager.hpp` cleanly manipulates `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` using `QSettings`. |
| **QML UI & Assets** | `librepods-org/librepods` / `Tblob18` | `Main.qml`, `BatteryIndicator.qml`, `SegmentedControl.qml`, `PodColumn.qml`, SF Symbols font, and AirPods png assets. |
| **L2CAP Bridge Socket (`WinL2capSocket`)** | `will-ch-h/librepods-windowsbridge` (`windows/`) | `winl2capsocket.cpp/h` encapsulates Win32 `SetupDi` device interface discovery and `CreateFile`/`ReadFile`/`WriteFile` against the AAP profile driver with an API matching `QBluetoothSocket`. *(For Phase 4)* |

### What Should Be Adapted

| Component | Target Adaptation | Rationale |
|---|---|---|
| **BLE Advertisement Parsing (`blemanager.cpp`)** | Adapt from `Tblob18` + enhance unencrypted fallback | In `Tblob18`, `bleDeviceFound` in `main.cpp` discards advertisement data if the user has not synced IRK/AES keys. However, Apple Proximity Pairing advertisements (type `0x07`, manufacturer `0x004C`) expose model ID, left/right/case battery levels (10% resolution), charging flags, and in-ear status completely unencrypted. We adapt this to immediately populate telemetry without requiring encryption keys. |
| **Connected AirPods Detection** | Hybrid approach | Combine Windows paired device checks (`QBluetoothLocalDevice` / Win32 Bluetooth enumeration) with BLE advertisement matching and driver interface enumeration when available. |
| **CMake Build System** | Adapt from `Tblob18` / `will-ch-h` | Configure standard Windows MSVC build with `Qt6::Quick`, `Qt6::Widgets`, `Qt6::Bluetooth`, Windows SDK libraries (`Ole32`, `User32`, `PowrProf`, `Setupapi`), and optional OpenSSL. |
| **System Tray Integration** | Adapt from `Tblob18` / `will-ch-h` | Ensure Windows taskbar tray notifications and dynamic icon rendering function reliably across Windows 10 and Windows 11 taskbars. |

### What Should NOT Be Copied

| Component | Source Repository | Reason to Exclude |
|---|---|---|
| **Entire C# / WPF Application** | `ivLis-Studio/librepods-windows` | User requirement is to keep this repository a fork of the official LibrePods project (Qt/C++). Rewriting in C# departs completely from upstream maintainability. |
| **Linux D-Bus & PulseAudio code** | `librepods-org/librepods` (`linux/`) | Platform-specific to Linux (libpulse, org.bluez, org.mpris). |
| **Direct `QBluetoothSocket(L2capProtocol)` on Windows** | `Tblob18/librepods-windows` | The Microsoft Bluetooth stack does not allow user-mode raw L2CAP sockets. `QBluetoothSocket` on Windows only supports RFCOMM. Calling L2CAP fails unconditionally. |

---

## 3. Technical Blockers & Architectural Resolution

### Milestone 1 (Phase 3): Telemetry & In-Ear State (NO DRIVER REQUIRED)
- **Problem**: Does reading AirPods battery, model, and in-ear state require a kernel driver?
- **Resolution**: **NO.** AirPods continuously broadcast BLE advertisements using Apple Manufacturer ID `0x004C` and Proximity Pairing format `0x07`.
  - Windows BLE APIs (`BluetoothLEAdvertisementWatcher`, accessible via `Qt6::Bluetooth` `QBluetoothDeviceDiscoveryAgent`) can scan these advertisements without administrative privileges or custom drivers.
  - Plaintext fields include:
    - **Model ID**: High/Low bytes mapping to AirPods 1/2/3/4/Pro/Max.
    - **Left/Right Pod Battery**: Upper and lower nibbles (0–10 = 0%–100%, 15 = disconnected).
    - **Case Battery**: Lower nibble of byte 7 (0–10 = 0%–100%).
    - **Charging Flags**: Bits in byte 7 for Left, Right, Case charging.
    - **In-Ear Detection**: Bit 1 & Bit 3 of status byte XORed with primary/case state.
  - Therefore, **Milestone 1 can function 100% in user-mode on standard Windows installations without Secure Boot changes or Test Mode**.

### Milestone 2 (Phase 4): AACP Noise Control & Conversation Awareness (DRIVER REQUIRED)
- **Problem**: Windows user-mode applications cannot open raw L2CAP connections (UUID `74ec2172-0bad-4d01-8f77-997b2be0722a`) required for AACP command dispatch.
- **Resolution**: Reusing `will-ch-h`'s `WinL2capSocket` and the KMDF profile driver (`l2cap-windowsdriver` / `bthecho`).
  - Strict adherence to the security directive: Driver installation and test mode will not be triggered automatically.
  - A clear diagnostic/fallback mode will inform the user when AACP L2CAP transport is unavailable while keeping telemetry active.

---

## 4. Implementation Roadmap

1. **Phase 2: Windows Foundation**
   - Create `windows/` in the official LibrePods fork.
   - Set up CMake configuration for Windows MSVC + Qt 6.
   - Implement `WindowsAudioController`, `WindowsSleepMonitor`, and `AutoStartManager`.
   - Implement telemetry-ready `BleManager` and `main.cpp`.
2. **Phase 3: First Working Milestone**
   - AirPods detection via paired device enumeration + BLE advertisement watcher.
   - Model identification, Left/Right/Case battery parsing, charging state, and in-ear state detection.
   - System tray display + debug logging.
   - Build verification with MSVC and Qt 6.
3. **Phase 4: AACP Control Bridge**
   - Integrate `WinL2capSocket`.
   - Security evaluation and user handoff report for driver prerequisites.

# Building LibrePods for Windows

This document details the build prerequisites, architecture, and step-by-step instructions for compiling and running the LibrePods Windows application.

---

## 1. Prerequisites

### Compilers & Toolchain
- **Windows 10 / 11 64-bit** (x64)
- **Visual Studio 2022** or **Visual Studio Build Tools** (MSVC v143+ / 19.x)
  - Workload: *Desktop development with C++*
  - Components: MSVC v143 x64/x86 build tools, Windows 10/11 SDK (10.0.19041 or newer)
- **CMake** (v3.16 or newer)
- **Ninja** (included automatically with Visual Studio Build Tools under `Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja`)

### Qt 6 Framework
- **Qt 6.7.x or 6.8.x** for **MSVC 2022 64-bit** (`win64_msvc2022_64`)
- Required Qt Modules:
  - `qtbase` (Core, Gui, Widgets)
  - `qtdeclarative` (Qml, Quick, QuickControls2)
  - `qtconnectivity` (Bluetooth)
  - `qtmultimedia` (Multimedia)
  - `qtsvg` (Svg)

#### Automated Qt 6 Installation via `aqtinstall`
If Qt 6 is not already installed on your system, install it cleanly via Python (no installer GUI or admin required):
```powershell
pip install aqtinstall
python -m aqt install-qt windows desktop 6.8.0 win64_msvc2022_64 -m qtconnectivity qtmultimedia -O C:\Qt -b https://mirrors.dotsrc.org/qtproject/
```

### Cryptography (Zero Third-Party Dependency)
Unlike the Linux implementation that links `libssl` and `libcrypto`, the Windows port utilizes the **Windows Cryptography API: Next Generation (CNG / BCrypt)** (`bcrypt.h` and `bcrypt.lib`), which is preinstalled on every Windows system. **No OpenSSL installation is required on Windows.**

---

## 2. Quick Build

From the repository root, run the automated build script:

```powershell
# Using PowerShell
.\windows-build.ps1

# Or from cmd.exe
windows-build.cmd
```

The script will:
1. Auto-detect your Visual Studio MSVC environment.
2. Initialize the 64-bit developer environment (`vcvars64.bat`).
3. Configure CMake with Ninja using `C:\Qt\6.8.0\msvc2022_64`.
4. Compile `librepods-windows.exe`.
5. Run `windeployqt` to bundle all runtime Qt DLLs and QML plugins into `build\`.

---

## 3. Manual Build via Command Line

If you prefer building step-by-step:

```cmd
:: 1. Open a Visual Studio x64 Developer Command Prompt (or run vcvars64.bat)
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

:: 2. Ensure Ninja and Qt binaries are on PATH
set PATH=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;C:\Qt\6.8.0\msvc2022_64\bin;%PATH%

:: 3. Configure CMake
cmake -S windows -B build -G Ninja -DCMAKE_PREFIX_PATH="C:/Qt/6.8.0/msvc2022_64" -DCMAKE_BUILD_TYPE=Release

:: 4. Build
cmake --build build

:: 5. Deploy Qt runtime DLLs
C:\Qt\6.8.0\msvc2022_64\bin\windeployqt.exe build\librepods-windows.exe --qmldir windows
```

---

## 4. Running & Debugging

Launch the application with the `--debug` flag to view live diagnostic logs directly in the console:

```powershell
.\build\librepods-windows.exe --debug
```

### Available Command-Line Options
- `--debug`: Enable verbose diagnostic logging for BLE advertisements, packet parsers, audio events, and socket state.
- `--hide`: Start minimized directly into the Windows system notification tray area.
- `--help`: Display available CLI flags.

---

## 5. Security & Operating Architecture

### Milestone 1 (Telemetry & In-Ear Detection)
- **Zero Driver Requirements**: Runs 100% in user-mode using Windows Bluetooth LE Advertisement Watcher via `Qt6::Bluetooth`.
- **No Test Mode**: Does NOT require `bcdedit /set testsigning on`.
- **No Secure Boot Changes**: Fully compatible with Secure Boot enabled.
- Detects AirPods model, parses Left/Right/Case battery levels, and updates in-ear status completely in user space.

### Milestone 2 (AACP ANC Control)
- ANC modes (Off, Noise Cancellation, Transparency, Adaptive) and Conversational Awareness control require access to the AirPods L2CAP control channel (`74ec2172-0bad-4d01-8f77-997b2be0722a`).
- Windows user-mode blocks raw L2CAP access; Phase 4 provides integration with the kernel-mode profile driver (`WinL2capSocket`).

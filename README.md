# PortalJump

PowerShell automation for accepting the ATT Wi-Fi captive portal after WLAN connect events.

This repo now uses one main script:
- captiveportal-attwifi.ps1

Modes:
- No switch: run worker flow (check SSID and handle captive portal acceptance)
- -Install: install/update scheduled task
- -Uninstall: remove scheduled task

## How it works

1. Run captiveportal-attwifi.ps1 -Install to create a SYSTEM Scheduled Task triggered by WLAN AutoConfig Event ID 8001.
2. On each WLAN connect event, captiveportal-attwifi.ps1 runs in worker mode (no mode switch).
3. Worker script exits quickly unless connected to target SSID (default: att-wifi).
4. If internet is not already available, worker script fetches captive portal form, submits acceptance, and verifies connectivity.

## Requirements

- Windows with PowerShell.
- Wireless networking enabled.
- Permission to run scripts in your environment.
- Administrator rights for install and uninstall operations.

## Default behavior

Current defaults are:
- ShowConsoleOutput is ON.
- ElevateIfNeeded is ON.

That means:
- The script prints INFO/WARN/ERROR lines to the terminal by default.
- Install/uninstall modes attempt UAC elevation automatically when launched from a non-elevated interactive session.

## Quick start

From this folder:

1) Install task

  .\captiveportal-attwifi.ps1 -Install

2) Verify worker manually (optional)

    .\captiveportal-attwifi.ps1

3) Uninstall task later

  .\captiveportal-attwifi.ps1 -Uninstall

## Script reference

### captiveportal-attwifi.ps1

Purpose:
- Single entrypoint for worker/install/uninstall operations.

Common parameters:
- Install
- Uninstall
- TargetSsid (default: att-wifi)
- PortalBaseUrl (default: http://192.0.2.123)
- InitialDelaySeconds (default: 6)
- MaxAttempts (default: 3)
- RequestTimeoutSeconds (default: 12)
- TaskName (default: AttWifi-CaptivePortal-Auto)
- LogPath (default: $env:ProgramData\AttWifiPortal\attwifi-captiveportal.log)
- ShowConsoleOutput (default: ON)
- ElevateIfNeeded (default: ON; relevant for install/uninstall)

Examples:

    .\captiveportal-attwifi.ps1
  .\captiveportal-attwifi.ps1 -Install
  .\captiveportal-attwifi.ps1 -Uninstall
    .\captiveportal-attwifi.ps1 -TargetSsid "att-wifi" -MaxAttempts 5
    .\captiveportal-attwifi.ps1 -ShowConsoleOutput:$false

## Logs

Default log files:
- Worker/Install/Uninstall: $env:ProgramData\AttWifiPortal\attwifi-captiveportal.log

Each line uses this format:
- YYYY-MM-DD HH:MM:SS [LEVEL] Message

## Troubleshooting

- Access is denied during install/uninstall:
  - Keep default ElevateIfNeeded ON and accept UAC prompt, or run elevated manually.
- Task created but worker does not run:
  - Confirm WLAN operational log is enabled and event trigger exists.
  - Confirm Scheduled Task action points to captiveportal-attwifi.ps1.
- Worker exits immediately:
  - Check log line for SSID mismatch or internet already available.
- Captive portal submission fails:
  - Verify PortalBaseUrl and target portal HTML fields have not changed.

## Safety notes

- Install/uninstall scripts modify Scheduled Tasks and event logging configuration.
- Install/uninstall modes modify Scheduled Tasks and event logging configuration.
- Worker script uses a named global mutex to prevent concurrent runs.
- Test in your environment before broad deployment.

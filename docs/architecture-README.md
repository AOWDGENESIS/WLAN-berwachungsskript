# Architecture

Guardian is designed as a modular local monitoring system. The system is separated into core runtime, FRITZ!Box integration, network and device telemetry, evidence recording, security control, and optional capture.

Important rules:

- Untrusted or unknown devices are represented as `unknown`, not as attackers.
- FRITZ!Box outages must result in `FRITZBOX_OFFLINE` or `DEGRADED` state, never a green safe state.
- Capture is opt-in and disabled by default.
- Evidence is hash-linked and audit-friendly.
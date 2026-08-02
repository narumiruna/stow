# ADR 0002: Share-Extension Capture Persistence

- Status: Accepted
- Date: 2026-08-02

## Decision

Share extensions do not open the SwiftData/CloudKit store. They normalize one `CaptureDraft`, copy any security-scoped attachment into an App Group staging directory, atomically rename a completed manifest directory into `CaptureSpool/Pending`, then finish. The host app ingests pending directories idempotently into SwiftData and is solely responsible for CloudKit synchronization.

## Evidence

`CaptureSpoolTests` exercise process-style reopen, atomic staging visibility, duplicate ingestion, attachment byte round trips, interruption cleanup, and malformed-manifest quarantine. This avoids concurrent cross-process SwiftData access and keeps CloudKit out of extension lifecycles. A signed-device CloudKit round trip remains a release-matrix check because it requires a provisioned container and two devices.

## Recovery

A manifest remains pending until the SwiftData transaction succeeds. Malformed captures move to quarantine rather than blocking valid captures. Hidden `.staging-*` directories are ignored and removed by host maintenance after interrupted extension writes.

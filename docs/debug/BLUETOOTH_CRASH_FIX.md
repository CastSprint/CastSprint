# Bluetooth Crash Fix

The 0.2.1 crash report records an explicit TCC termination: CastSprint accessed CoreBluetooth without `NSBluetoothAlwaysUsageDescription`.

Version 0.2.2 adds the required purpose string, uses one process-lifetime Bluetooth provider, waits for `centralManagerDidUpdateState`, scans only in `.poweredOn`, prevents duplicate scans, and stops scanning for every unavailable state. Bluetooth remains optional discovery assistance and is never a media transport.

Build verification passes. Permission-denied/powered-off UI testing remains pending.

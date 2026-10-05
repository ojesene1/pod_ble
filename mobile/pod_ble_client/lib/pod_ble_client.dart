/// BLE client for the WB pod's Step Record Service.
///
/// Protocol: protocol/GATT.md in the pod-ble repo.
library;

export 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothAdapterState, BluetoothConnectionState, BluetoothDevice, FlutterBluePlus, ScanResult;

export 'src/pod_connection.dart';
export 'src/protocol.dart';

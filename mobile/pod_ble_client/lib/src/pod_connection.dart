// BLE transport for the pod, built on flutter_blue_plus.
//
// Implements the "expected app flow" in protocol/GATT.md:
// scan by service UUID -> connect -> SET_TIME -> read Status -> subscribe.

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'protocol.dart';

/// Licence passed to flutter_blue_plus on connect. The capstone qualifies as
/// educational use; this must become [License.commercial] (a paid licence) if
/// the product is ever sold.
const License podBleLicense = License.nonprofit;

final Guid _serviceGuid = Guid(PodUuids.stepService);
final Guid _recordGuid = Guid(PodUuids.stepRecord);
final Guid _controlGuid = Guid(PodUuids.controlPoint);
final Guid _statusGuid = Guid(PodUuids.status);

/// Finding pods.
abstract final class PodScanner {
  /// Starts scanning for pods (devices advertising the Step Record Service).
  /// Results arrive on [results]. Android asks for Bluetooth permissions here.
  static Future<void> start({Duration timeout = const Duration(seconds: 15)}) =>
      FlutterBluePlus.startScan(withServices: [_serviceGuid], timeout: timeout);

  static Future<void> stop() => FlutterBluePlus.stopScan();

  /// Pods seen in the current scan, updated as advertisements arrive.
  static Stream<List<ScanResult>> get results => FlutterBluePlus.onScanResults;

  static Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Bluetooth on/off/unauthorized. Show a prompt unless this is [BluetoothAdapterState.on].
  static Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;
}

/// An open, set-up connection to one pod.
class PodConnection {
  PodConnection._(this.device, this._record, this._control, this._status);

  final BluetoothDevice device;
  final BluetoothCharacteristic _record;
  final BluetoothCharacteristic _control;
  final BluetoothCharacteristic _status;

  /// Stable identifier for this pod on this phone. Store records keyed by
  /// (podId, seq). Note: on iOS this is a per-phone UUID, not the BLE address.
  String get podId => device.remoteId.str;

  Stream<BluetoothConnectionState> get connectionState => device.connectionState;

  /// Connects, finds the Step Record Service, sets the pod clock and checks
  /// protocol versions. Throws [PodProtocolException] if the pod is incompatible.
  static Future<PodConnection> connect(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // On Android this also requests a 512-byte MTU; iOS negotiates it automatically.
    await device.connect(license: podBleLicense, timeout: timeout);
    try {
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == _serviceGuid,
        orElse: () => throw PodProtocolException('Step Record Service not found'),
      );
      BluetoothCharacteristic find(Guid uuid) => service.characteristics.firstWhere(
            (c) => c.uuid == uuid,
            orElse: () => throw PodProtocolException('characteristic $uuid not found'),
          );

      final conn = PodConnection._(device, find(_recordGuid), find(_controlGuid), find(_statusGuid));
      await conn.syncTime();
      final status = await conn.readStatus();
      if (!status.isCompatible) {
        throw PodProtocolException('pod speaks $status; app expects protocol v$podProtocolVersion, '
            'record v${StepRecord.version}');
      }
      return conn;
    } catch (_) {
      await device.disconnect();
      rethrow;
    }
  }

  /// Sends the phone's current time to the pod.
  Future<void> syncTime([DateTime? now]) => _control.write(ControlPoint.setTime(now ?? DateTime.now()));

  Future<PodStatus> readStatus() async => PodStatus.fromBytes(await _status.read());

  /// Tells the pod every record up to [seq] is stored durably on the phone.
  /// Call only after the record is persisted, never just on receipt.
  Future<void> ack(int seq) => _control.write(ControlPoint.ack(seq));

  /// Subscribes to step records. The pod first drains its buffer, then streams
  /// live steps. The stream closes when the pod disconnects.
  ///
  /// Delivery is at-least-once: after a dropped link the pod may resend the
  /// last record, so dedup on (podId, seq).
  Stream<StepRecord> records() {
    late final StreamController<StepRecord> controller;
    StreamSubscription<List<int>>? valueSub;
    StreamSubscription<BluetoothConnectionState>? stateSub;

    Future<void> cleanUp() async {
      await valueSub?.cancel();
      await stateSub?.cancel();
      valueSub = null;
      stateSub = null;
    }

    controller = StreamController<StepRecord>(
      onListen: () async {
        valueSub = _record.onValueReceived.listen(
          (bytes) {
            try {
              StepRecord.parseNotification(bytes).forEach(controller.add);
            } on PodProtocolException catch (e, st) {
              controller.addError(e, st);
            }
          },
          onError: controller.addError,
        );
        stateSub = device.connectionState.listen((state) async {
          if (state == BluetoothConnectionState.disconnected) {
            await cleanUp();
            await controller.close();
          }
        });
        try {
          await _record.setNotifyValue(true);
        } catch (e, st) {
          controller.addError(e, st);
        }
      },
      onCancel: () async {
        await cleanUp();
        if (device.isConnected) {
          try {
            await _record.setNotifyValue(false);
          } catch (_) {
            // Link may be going down; nothing useful to do.
          }
        }
      },
    );
    return controller.stream;
  }

  Future<void> disconnect() => device.disconnect();
}

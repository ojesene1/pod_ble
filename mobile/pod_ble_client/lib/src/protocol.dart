// On-air formats for the pod <-> app BLE link.
//
// This file is the app's copy of the contract in protocol/GATT.md; the firmware's
// copy is firmware/pod-protocol/src/lib.rs. Change all three together.
// Pure Dart (no Flutter imports) so it can be unit-tested and reused anywhere.
//
// All multi-byte fields are little-endian.

import 'dart:typed_data';

/// Bumped on any change to the service layout or control-point opcodes.
const int podProtocolVersion = 0;

/// 128-bit UUIDs. Base: fbe3xxxx-fc86-4926-b9db-293cbba6fc2f.
abstract final class PodUuids {
  static const String stepService = 'fbe30001-fc86-4926-b9db-293cbba6fc2f';
  static const String stepRecord = 'fbe30002-fc86-4926-b9db-293cbba6fc2f';
  static const String controlPoint = 'fbe30003-fc86-4926-b9db-293cbba6fc2f';
  static const String status = 'fbe30004-fc86-4926-b9db-293cbba6fc2f';
}

/// Thrown when bytes from the pod don't match the expected format.
class PodProtocolException implements Exception {
  PodProtocolException(this.message);
  final String message;

  @override
  String toString() => 'PodProtocolException: $message';
}

/// Per-step summary sent by the pod (18 bytes).
///
/// DRAFT v0: field set still to be agreed with Platforms before the backend
/// schema is fixed.
class StepRecord {
  const StepRecord({
    required this.seq,
    required this.timestampS,
    required this.peakForceDn,
    required this.peakBwPermille,
    required this.impulseDns,
    required this.stanceMs,
    required this.heelPct,
    required this.flags,
  });

  static const int version = 0;
  static const int length = 18;

  static const int flagOverLimit = 0x01;
  static const int flagTimeSynced = 0x02;
  static const int flagSensorFault = 0x04;

  /// Sequence number, monotonic within one pod boot. Use it to dedup.
  final int seq;

  /// UTC epoch seconds if [timeSynced], otherwise seconds since pod boot.
  final int timestampS;

  /// Peak total force, 0.1 N units.
  final int peakForceDn;

  /// Peak force as % body weight x10.
  final int peakBwPermille;

  /// Force-time integral, 0.1 N*s units.
  final int impulseDns;

  /// Stance duration in ms.
  final int stanceMs;

  /// Heel zone's share of peak load, 0-100.
  final int heelPct;

  /// Raw flag bits; prefer the getters below.
  final int flags;

  double get peakForceN => peakForceDn / 10;
  double get peakBodyWeightPct => peakBwPermille / 10;
  double get impulseNs => impulseDns / 10;
  Duration get stance => Duration(milliseconds: stanceMs);
  bool get overLimit => (flags & flagOverLimit) != 0;
  bool get timeSynced => (flags & flagTimeSynced) != 0;
  bool get sensorFault => (flags & flagSensorFault) != 0;

  /// UTC time of the step, or null if the pod's clock hadn't been set.
  DateTime? get timestamp =>
      timeSynced ? DateTime.fromMillisecondsSinceEpoch(timestampS * 1000, isUtc: true) : null;

  factory StepRecord.fromBytes(List<int> bytes) {
    if (bytes.length != length) {
      throw PodProtocolException('step record must be $length bytes, got ${bytes.length}');
    }
    final b = ByteData.sublistView(Uint8List.fromList(bytes));
    return StepRecord(
      seq: b.getUint32(0, Endian.little),
      timestampS: b.getUint32(4, Endian.little),
      peakForceDn: b.getUint16(8, Endian.little),
      peakBwPermille: b.getUint16(10, Endian.little),
      impulseDns: b.getUint16(12, Endian.little),
      stanceMs: b.getUint16(14, Endian.little),
      heelPct: b.getUint8(16),
      flags: b.getUint8(17),
    );
  }

  /// Splits one notification into records. v0 sends one record per notification;
  /// this already accepts several back to back for when batching is added.
  static List<StepRecord> parseNotification(List<int> bytes) {
    if (bytes.isEmpty || bytes.length % length != 0) {
      throw PodProtocolException('notification length ${bytes.length} is not a multiple of $length');
    }
    return [
      for (var i = 0; i < bytes.length; i += length) StepRecord.fromBytes(bytes.sublist(i, i + length)),
    ];
  }

  /// Encodes the record (useful for fakes and tests).
  Uint8List toBytes() {
    final b = ByteData(length)
      ..setUint32(0, seq, Endian.little)
      ..setUint32(4, timestampS, Endian.little)
      ..setUint16(8, peakForceDn, Endian.little)
      ..setUint16(10, peakBwPermille, Endian.little)
      ..setUint16(12, impulseDns, Endian.little)
      ..setUint16(14, stanceMs, Endian.little)
      ..setUint8(16, heelPct)
      ..setUint8(17, flags);
    return b.buffer.asUint8List();
  }

  Map<String, Object?> toJson() => {
        'seq': seq,
        'timestamp_s': timestampS,
        'time_synced': timeSynced,
        'peak_force_n': peakForceN,
        'peak_bw_pct': peakBodyWeightPct,
        'impulse_ns': impulseNs,
        'stance_ms': stanceMs,
        'heel_pct': heelPct,
        'over_limit': overLimit,
        'sensor_fault': sensorFault,
      };

  @override
  bool operator ==(Object other) =>
      other is StepRecord &&
      other.seq == seq &&
      other.timestampS == timestampS &&
      other.peakForceDn == peakForceDn &&
      other.peakBwPermille == peakBwPermille &&
      other.impulseDns == impulseDns &&
      other.stanceMs == stanceMs &&
      other.heelPct == heelPct &&
      other.flags == flags;

  @override
  int get hashCode =>
      Object.hash(seq, timestampS, peakForceDn, peakBwPermille, impulseDns, stanceMs, heelPct, flags);

  @override
  String toString() => 'StepRecord(seq: $seq, ${peakBodyWeightPct.toStringAsFixed(1)} %BW'
      '${overLimit ? ', OVER LIMIT' : ''})';
}

/// Value of the Status characteristic (5 bytes).
class PodStatus {
  const PodStatus({
    required this.protocolVersion,
    required this.recordVersion,
    required this.pending,
    required this.flags,
  });

  static const int length = 5;
  static const int flagTimeSynced = 0x01;

  final int protocolVersion;
  final int recordVersion;

  /// Records still waiting on the pod.
  final int pending;
  final int flags;

  bool get timeSynced => (flags & flagTimeSynced) != 0;

  /// True if this app understands the pod's protocol and record versions.
  bool get isCompatible => protocolVersion == podProtocolVersion && recordVersion == StepRecord.version;

  factory PodStatus.fromBytes(List<int> bytes) {
    if (bytes.length < length) {
      throw PodProtocolException('status must be at least $length bytes, got ${bytes.length}');
    }
    final b = ByteData.sublistView(Uint8List.fromList(bytes));
    return PodStatus(
      protocolVersion: b.getUint8(0),
      recordVersion: b.getUint8(1),
      pending: b.getUint16(2, Endian.little),
      flags: b.getUint8(4),
    );
  }

  @override
  String toString() =>
      'PodStatus(protocol v$protocolVersion, record v$recordVersion, pending: $pending, timeSynced: $timeSynced)';
}

/// Encoders for writes to the Control Point characteristic.
abstract final class ControlPoint {
  static const int opSetTime = 0x01;
  static const int opAck = 0x02;

  /// Sets the pod clock. Send on every connect.
  static Uint8List setTime(DateTime time) =>
      _opWithU32(opSetTime, time.toUtc().millisecondsSinceEpoch ~/ 1000);

  /// Tells the pod everything up to and including [seq] is stored durably on the phone.
  static Uint8List ack(int seq) => _opWithU32(opAck, seq);

  static Uint8List _opWithU32(int op, int value) {
    final b = ByteData(5)
      ..setUint8(0, op)
      ..setUint32(1, value, Endian.little);
    return b.buffer.asUint8List();
  }
}

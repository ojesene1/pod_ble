import 'package:flutter_test/flutter_test.dart';
import 'package:pod_ble_client/src/protocol.dart';

// Golden vectors: identical bytes are asserted in firmware/pod-protocol (Rust)
// and listed in protocol/GATT.md. If one side changes, all three must.
const goldenRecordBytes = [
  0x02, 0x01, 0x00, 0x00, 0x54, 0xc1, 0xc3, 0x6a, 0xc1, 0x0d, //
  0xf7, 0x01, 0xe0, 0x06, 0x64, 0x02, 0x2a, 0x03,
];
const goldenStatusBytes = [0x00, 0x00, 0x07, 0x00, 0x01];

void main() {
  group('StepRecord', () {
    test('decodes the golden vector', () {
      final r = StepRecord.fromBytes(goldenRecordBytes);
      expect(r.seq, 258);
      expect(r.timestampS, 1791213908);
      expect(r.peakForceDn, 3521);
      expect(r.peakForceN, closeTo(352.1, 1e-9));
      expect(r.peakBwPermille, 503);
      expect(r.peakBodyWeightPct, closeTo(50.3, 1e-9));
      expect(r.impulseDns, 1760);
      expect(r.stanceMs, 612);
      expect(r.heelPct, 42);
      expect(r.overLimit, isTrue);
      expect(r.timeSynced, isTrue);
      expect(r.sensorFault, isFalse);
      expect(r.timestamp, DateTime.utc(2026, 10, 5, 15, 25, 8));
    });

    test('round-trips through toBytes', () {
      expect(StepRecord.fromBytes(goldenRecordBytes).toBytes(), goldenRecordBytes);
    });

    test('timestamp is null until the pod clock is set', () {
      final bytes = [...goldenRecordBytes]..[17] = StepRecord.flagOverLimit;
      expect(StepRecord.fromBytes(bytes).timestamp, isNull);
    });

    test('rejects wrong lengths', () {
      expect(() => StepRecord.fromBytes(goldenRecordBytes.sublist(0, 17)), throwsA(isA<PodProtocolException>()));
      expect(() => StepRecord.parseNotification(const []), throwsA(isA<PodProtocolException>()));
      expect(() => StepRecord.parseNotification(List.filled(19, 0)), throwsA(isA<PodProtocolException>()));
    });

    test('parses batched notifications', () {
      final records = StepRecord.parseNotification([...goldenRecordBytes, ...goldenRecordBytes]);
      expect(records, hasLength(2));
      expect(records.first, records.last);
    });
  });

  group('PodStatus', () {
    test('decodes the golden vector', () {
      final s = PodStatus.fromBytes(goldenStatusBytes);
      expect(s.protocolVersion, 0);
      expect(s.recordVersion, 0);
      expect(s.pending, 7);
      expect(s.timeSynced, isTrue);
      expect(s.isCompatible, isTrue);
    });
  });

  group('ControlPoint', () {
    test('encodes SET_TIME', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1791213908 * 1000, isUtc: true);
      expect(ControlPoint.setTime(t), [0x01, 0x54, 0xc1, 0xc3, 0x6a]);
    });

    test('encodes ACK', () {
      expect(ControlPoint.ack(258), [0x02, 0x02, 0x01, 0x00, 0x00]);
    });
  });
}

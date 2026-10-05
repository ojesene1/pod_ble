// Bench-test app: scan for pods, connect to one, and watch step records arrive.
// Not the patient app; it exists so the BLE link can be tested end to end.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pod_ble_client/pod_ble_client.dart';

void main() => runApp(const PodBenchApp());

class PodBenchApp extends StatelessWidget {
  const PodBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pod BLE bench',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const ScanPage(),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(PodScanner.results.listen((r) => setState(() => _results = r)))
      ..add(PodScanner.isScanning.listen((s) => setState(() => _scanning = s)))
      ..add(PodScanner.adapterState.listen((s) => setState(() => _adapter = s)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _toggleScan() async {
    try {
      _scanning ? await PodScanner.stop() : await PodScanner.start();
    } catch (e) {
      _snack('Scan failed: $e');
    }
  }

  Future<void> _open(ScanResult r) async {
    await PodScanner.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PodPage(device: r.device)));
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final btOn = _adapter == BluetoothAdapterState.on;
    return Scaffold(
      appBar: AppBar(title: const Text('Find a pod')),
      body: Column(
        children: [
          if (!btOn)
            MaterialBanner(
              content: Text('Bluetooth is ${_adapter.name}. Turn it on to scan.'),
              actions: const [SizedBox.shrink()],
            ),
          if (_scanning) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text(_scanning ? 'Scanning…' : 'Tap Scan to look for pods'))
                : ListView(
                    children: [
                      for (final r in _results)
                        ListTile(
                          leading: const Icon(Icons.sensors),
                          title: Text(r.advertisementData.advName.isEmpty ? 'Pod' : r.advertisementData.advName),
                          subtitle: Text(r.device.remoteId.str),
                          trailing: Text('${r.rssi} dBm'),
                          onTap: () => _open(r),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: btOn ? _toggleScan : null,
        icon: Icon(_scanning ? Icons.stop : Icons.search),
        label: Text(_scanning ? 'Stop' : 'Scan'),
      ),
    );
  }
}

class PodPage extends StatefulWidget {
  const PodPage({super.key, required this.device});
  final BluetoothDevice device;

  @override
  State<PodPage> createState() => _PodPageState();
}

class _PodPageState extends State<PodPage> {
  static const _keep = 100;

  PodConnection? _conn;
  PodStatus? _status;
  String _state = 'Connecting…';
  final List<StepRecord> _records = [];
  final Set<int> _seen = {};
  StreamSubscription<StepRecord>? _sub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final conn = await PodConnection.connect(widget.device);
      final status = await conn.readStatus();
      if (!mounted) {
        await conn.disconnect();
        return;
      }
      setState(() {
        _conn = conn;
        _status = status;
        _state = 'Connected';
      });
      _sub = conn.records().listen(
        (r) {
          if (!_seen.add(r.seq)) return; // at-least-once delivery: drop resends
          setState(() {
            _records.insert(0, r);
            if (_records.length > _keep) _records.removeLast();
          });
        },
        onError: (Object e) => setState(() => _state = 'Error: $e'),
        onDone: () {
          if (mounted) setState(() => _state = 'Disconnected');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _state = 'Failed: $e');
    }
  }

  Future<void> _refreshStatus() async {
    final conn = _conn;
    if (conn == null) return;
    try {
      final s = await conn.readStatus();
      setState(() => _status = s);
    } catch (e) {
      setState(() => _state = 'Error: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _conn?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.remoteId.str),
        actions: [IconButton(onPressed: _refreshStatus, icon: const Icon(Icons.refresh), tooltip: 'Read status')],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '$_state\n'
              '${s == null ? '' : 'Pending on pod: ${s.pending} · clock ${s.timeSynced ? 'synced' : 'not synced'} · '
                  'protocol v${s.protocolVersion}'}\n'
              'Received: ${_seen.length}',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _records.length,
              itemBuilder: (_, i) {
                final r = _records[i];
                final when = r.timestamp?.toLocal().toIso8601String().substring(11, 19) ?? '+${r.timestampS}s';
                return ListTile(
                  dense: true,
                  leading: Icon(r.overLimit ? Icons.warning_amber : Icons.directions_walk,
                      color: r.overLimit ? Colors.red : null),
                  title: Text('${r.peakBodyWeightPct.toStringAsFixed(1)} %BW  ·  ${r.peakForceN.toStringAsFixed(0)} N'),
                  subtitle: Text('#${r.seq}  $when  stance ${r.stanceMs} ms  heel ${r.heelPct}%'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

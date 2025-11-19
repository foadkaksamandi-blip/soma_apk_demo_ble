import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() {
  runApp(const SomaBluetoothCoreApp());
}

class SomaBluetoothCoreApp extends StatelessWidget {
  const SomaBluetoothCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soma Bluetooth Core',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00BFA5)),
        useMaterial3: true,
      ),
      home: const BluetoothCorePage(),
    );
  }
}

/// صفحه‌ی دمو برای هسته‌ی بلوتوث.
/// این همون چیزی‌ه که بعداً منطقش رو می‌کشیم تو اپ خریدار/فروشنده.
class BluetoothCorePage extends StatefulWidget {
  const BluetoothCorePage({super.key});

  @override
  State<BluetoothCorePage> createState() => _BluetoothCorePageState();
}

class _BluetoothCorePageState extends State<BluetoothCorePage> {
  final FlutterBlue _flutterBlue = FlutterBlue.instance;

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;

  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  List<BluetoothService> _services = [];

  BluetoothCharacteristic? _txChar; // برای ارسال
  BluetoothCharacteristic? _rxChar; // برای دریافت

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _messageLogController = TextEditingController();

  static const String _serviceUuidStr =
      '0000FEED-0000-1000-8000-00805F9B34FB'; // نمونه
  static const String _txUuidStr =
      '0000FEF1-0000-1000-8000-00805F9B34FB'; // نمونه
  static const String _rxUuidStr =
      '0000FEF2-0000-1000-8000-00805F9B34FB'; // نمونه

  Guid get _serviceUuid => Guid(_serviceUuidStr);
  Guid get _txUuid => Guid(_txUuidStr);
  Guid get _rxUuid => Guid(_rxUuidStr);

  @override
  void initState() {
    super.initState();
    _checkAdapterState();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _disconnect();
    _amountController.dispose();
    _messageLogController.dispose();
    super.dispose();
  }

  Future<void> _checkAdapterState() async {
    // فقط برای لاگ ساده
    _flutterBlue.state.listen((state) {
      _appendLog('Bluetooth state: $state');
    });
  }

  void _appendLog(String line) {
    _messageLogController.text =
        '${_messageLogController.text}$line\n';
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    _scanResults = [];
    setState(() {
      _isScanning = true;
    });

    _appendLog('Start scanning for devices...');

    _scanSub?.cancel();
    _scanSub = _flutterBlue.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });

    await _flutterBlue.startScan(timeout: const Duration(seconds: 6));

    await _flutterBlue.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;

    setState(() {
      _isScanning = false;
    });

    _appendLog('Scan finished. Found ${_scanResults.length} device(s).');
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _appendLog('Connecting to ${device.name} (${device.id}) ...');

    try {
      await device.connect();
    } on Exception catch (e) {
      _appendLog('Connect error: $e');
      return;
    }

    _connectedDevice = device;
    _appendLog('Connected to ${device.name}. Discovering services...');

    _services = await device.discoverServices();

    BluetoothCharacteristic? tx;
    BluetoothCharacteristic? rx;

    for (final service in _services) {
      if (service.uuid == _serviceUuid) {
        for (final c in service.characteristics) {
          if (c.uuid == _txUuid) {
            tx = c;
          } else if (c.uuid == _rxUuid) {
            rx = c;
          }
        }
      }
    }

    _txChar = tx;
    _rxChar = rx;

    if (_rxChar != null) {
      await _rxChar!.setNotifyValue(true);
      _rxChar!.value.listen((value) {
        final text = utf8.decode(value);
        _appendLog('RECV: $text');
      });
    } else {
      _appendLog(
          'Warning: RX characteristic not found. Receive will not work yet.');
    }

    setState(() {});

    _appendLog('Bluetooth core is ready.');
  }

  Future<void> _disconnect() async {
    final device = _connectedDevice;
    _connectedDevice = null;
    _txChar = null;
    _rxChar = null;
    _services = [];

    if (device != null) {
      _appendLog('Disconnecting from ${device.name} ...');
      try {
        await device.disconnect();
      } catch (_) {}
    }

    setState(() {});
  }

  Future<void> _sendSomaMessage() async {
    if (_txChar == null) {
      _appendLog('TX characteristic not ready.');
      return;
    }

    final amount = _amountController.text.trim();
    if (amount.isEmpty) {
      _appendLog('Amount is empty.');
      return;
    }

    // پروتکل ساده متنی برای دمو:
    // SOMA_V1|AMOUNT=<amount>|TS=<timestamp>
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = 'SOMA_V1|AMOUNT=$amount|TS=$now';

    final bytes = utf8.encode(payload);
    try {
      await _txChar!.write(bytes, withoutResponse: false);
      _appendLog('SEND: $payload');
    } catch (e) {
      _appendLog('Write error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connectedDevice != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soma Bluetooth Core'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: const Icon(Icons.search),
                    label: Text(_isScanning ? 'در حال اسکن...' : 'اسکن بلوتوث'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: connected ? _disconnect : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('قطع اتصال'),
                  ),
                ),
              ],
            ),
          ),
          if (!connected)
            Expanded(
              child: _buildScanResultsList(),
            )
          else
            Expanded(
              child: _buildConnectedView(),
            ),
        ],
      ),
    );
  }

  Widget _buildScanResultsList() {
    if (_scanResults.isEmpty) {
      return const Center(
        child: Text('هیچ دیوایسی پیدا نشد. اسکن را شروع کن.'),
      );
    }

    return ListView.builder(
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        final r = _scanResults[index];
        final device = r.device;

        final name = device.name.isEmpty ? '(بدون نام)' : device.name;
        return ListTile(
          leading: const Icon(Icons.bluetooth),
          title: Text(name),
          subtitle: Text(device.id.id),
          trailing: Text(r.rssi.toString()),
          onTap: () => _connectToDevice(device),
        );
      },
    );
  }

  Widget _buildConnectedView() {
    final device = _connectedDevice!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'متصل به: ${device.name.isEmpty ? device.id.id : device.name}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'مبلغ (Amount)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _sendSomaMessage,
            icon: const Icon(Icons.send),
            label: const Text('ارسال پیام سوما'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Log',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TextField(
              controller: _messageLogController,
              maxLines: null,
              expands: true,
              readOnly: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

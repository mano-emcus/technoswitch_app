import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usb_serial/usb_serial.dart';
import 'services/usb_serial_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TechnoSwitch App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'TechnoSwitch Connection'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final UsbSerialService _serialService = UsbSerialService();
  List<UsbDevice> _devices = [];
  UsbDevice? _selectedDevice;
  String _status = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
    _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    final devices = await _serialService.getAvailablePorts();
    setState(() {
      _devices = devices;
      if (_devices.isEmpty) {
        _status = 'No USB devices found';
      }
    });
  }

  Future<void> _connect() async {
    if (_selectedDevice == null) return;

    final success = await _serialService.connect(_selectedDevice!);
    setState(() {
      _status =
          success
              ? 'Connected to ${_selectedDevice!.deviceId}'
              : 'Connection failed';
    });
  }

  Future<void> _disconnect() async {
    await _serialService.disconnect();
    setState(() {
      _status = 'Disconnected';
      _selectedDevice = null;
    });
  }

  Future<void> _sendTestMessage() async {
    // Example test message for Technoswitch Oryx 204
    // You'll need to adjust this based on the actual protocol
    final testMessage = [0x02, 0x00, 0x01, 0x03]; // STX, Length, Command, ETX
    final success = await _serialService.sendData(testMessage);
    setState(() {
      _status = success ? 'Test message sent' : 'Failed to send message';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: $_status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<UsbDevice>(
                            hint: const Text('Select Device'),
                            value: _selectedDevice,
                            items:
                                _devices.map((device) {
                                  return DropdownMenuItem<UsbDevice>(
                                    value: device,
                                    child: Text(
                                      '${device.vid}:${device.pid} (${device.manufacturerName ?? "Unknown"})',
                                    ),
                                  );
                                }).toList(),
                            onChanged: (device) {
                              setState(() {
                                _selectedDevice = device;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: _refreshDevices,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  _selectedDevice == null
                      ? null
                      : (_serialService.isConnected ? _disconnect : _connect),
              child: Text(
                _serialService.isConnected ? 'Disconnect' : 'Connect',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _serialService.isConnected ? _sendTestMessage : null,
              child: const Text('Send Test Message'),
            ),
          ],
        ),
      ),
    );
  }
}

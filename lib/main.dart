import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usb_serial/usb_serial.dart';
import 'services/usb_serial_service.dart';
import 'services/techno_switch_protocol.dart';

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
  String _lastResponse = '';
  bool _forceRhino103 = false;
  
  // Protocol settings
  final _masterAddressController = TextEditingController(text: '1');
  final _slaveAddressController = TextEditingController(text: '2');

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _masterAddressController.dispose();
    _slaveAddressController.dispose();
    super.dispose();
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

    // Parse addresses
    int? masterAddress;
    int? slaveAddress;
    try {
      masterAddress = int.parse(_masterAddressController.text);
      slaveAddress = int.parse(_slaveAddressController.text);
      if (masterAddress < 0 || masterAddress > 255 || 
          slaveAddress < 0 || slaveAddress > 255) {
        setState(() {
          _status = 'Invalid address (must be 0-255)';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _status = 'Invalid address format';
      });
      return;
    }

    final success = await _serialService.connect(
      _selectedDevice!,
      masterAddress: masterAddress,
      slaveAddress: slaveAddress,
    );
    
    setState(() {
      _status = success
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

  Future<void> _sendModuleIdRequest() async {
    final response = await _serialService.sendCommand([TechnoSwitchProtocol.CMD_MODULE_ID]);
    setState(() {
      if (response != null) {
        final data = _serialService.protocol?.extractData(response);
        _lastResponse = data != null 
            ? 'Module ID: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}'
            : 'Invalid response format';
      } else {
        _lastResponse = 'No response received';
      }
    });
  }

  Future<void> _sendModulePollRequest() async {
    final response = await _serialService.sendCommand([TechnoSwitchProtocol.CMD_MODULE_POLL]);
    setState(() {
      if (response != null) {
        final data = _serialService.protocol?.extractData(response);
        _lastResponse = data != null 
            ? 'Module Status: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}'
            : 'Invalid response format';
      } else {
        _lastResponse = 'No response received';
      }
    });
  }

  void _toggleForceRhino103(bool? value) {
    if (value != null) {
      setState(() {
        _forceRhino103 = value;
        _serialService.setForceRhino103(value);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
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
                    const Text(
                      'Device Connection',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Force RHINO103 Mode'),
                      subtitle: const Text('Use this if device reports as RHINO203 but is actually RHINO103'),
                      value: _forceRhino103,
                      onChanged: _toggleForceRhino103,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<UsbDevice>(
                            hint: const Text('Select Device'),
                            value: _selectedDevice,
                            items: _devices.map((device) {
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _masterAddressController,
                            decoration: const InputDecoration(
                              labelText: 'Master Address (0-255)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _slaveAddressController,
                            decoration: const InputDecoration(
                              labelText: 'Slave Address (0-255)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connection Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    if (_lastResponse.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Last Response: $_lastResponse'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device Commands',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _selectedDevice == null 
                      ? null
                      : (_serialService.isConnected ? _disconnect : _connect),
              child: Text(
                _serialService.isConnected ? 'Disconnect' : 'Connect',
              ),
            ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _serialService.isConnected ? _sendModuleIdRequest : null,
                            child: const Text('Get Module ID'),
                          ),
            ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _serialService.isConnected ? _sendModulePollRequest : null,
                            child: const Text('Poll Module'),
            ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

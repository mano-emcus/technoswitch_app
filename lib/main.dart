import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Device Communication Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: DeviceCommunicationScreen(),
    );
  }
}

class DeviceCommunicationScreen extends StatefulWidget {
  @override
  _DeviceCommunicationScreenState createState() => _DeviceCommunicationScreenState();
}

class _DeviceCommunicationScreenState extends State<DeviceCommunicationScreen> {
  // USB Serial connection objects
  UsbPort? _port;
  List<UsbDevice> _devices = [];
  StreamSubscription<Uint8List>? _subscription;
  
  // Control variables
  bool _isConnected = false;
  String _status = "Disconnected";
  String _receivedData = "";
  
  // Define the TX packet (MODULE_GENERAL_STATUS command)
  final Uint8List _txPacket = Uint8List.fromList([
    0xFE, // SOT (Start of Transmission)
    0x01, // DES (Destination)
    0x00, // ORI (Origin)
    0x04, // TYP (Type) - MODULE_GENERAL_STATUS
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0xB1, 0x4A, 0xFD  // EOT (End of Transmission)
  ]);
  
  // Packet format constants
  final int _packetStartByte = 0xFE;
  final int _packetEndByte = 0xFD;
  
  @override
  void initState() {
    super.initState();
    _initUsbSerial();
  }
  
  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
  
  // Initialize USB Serial and scan for available devices
  Future<void> _initUsbSerial() async {
    UsbSerial.usbEventStream?.listen((UsbEvent event) {
      print("USB Event: ${event.event}, device: ${event.device?.productName}");
      _refreshDeviceList();
    });
    
    await _refreshDeviceList();
  }
  
  // Refresh the list of available USB devices
  Future<void> _refreshDeviceList() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    print("Found ${devices.length} USB devices");
    
    setState(() {
      _devices = devices;
      if (_devices.isEmpty) {
        _status = "No USB devices found";
      } else {
        _status = "${_devices.length} USB ${_devices.length == 1 ? 'device' : 'devices'} found";
      }
    });
  }
  
  // Connect to a USB device
  Future<void> _connectToDevice(UsbDevice device) async {
    _disconnect();
    
    setState(() {
      _status = "Connecting to ${device.productName}...";
    });
    
    try {
      _port = await device.create();
      
      if (_port == null) {
        setState(() {
          _status = "Failed to create port for ${device.productName}";
        });
        return;
      }
      
      bool openResult = await _port!.open();
      if (!openResult) {
        setState(() {
          _status = "Failed to open port for ${device.productName}";
        });
        return;
      }
      
      // Configure port parameters
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      
      // Listen for incoming data
      _subscription = _port!.inputStream!.listen(
        (Uint8List data) {
          print("Data received: ${_bytesToHex(data)} (${data.length} bytes)");
          _onDataReceived(data);
        },
        onError: (error) {
          print("Stream error: $error");
          setState(() {
            _status = "Communication error: $error";
          });
        },
        onDone: () {
          print("Stream closed");
          setState(() {
            _status = "Connection closed";
            _isConnected = false;
          });
        },
      );
      
      setState(() {
        _isConnected = true;
        _status = "Connected to ${device.productName}";
      });
      
    } catch (e) {
      print("Error connecting to device: $e");
      setState(() {
        _status = "Error: ${e.toString()}";
      });
    }
  }
  
  // Disconnect from the current device
  void _disconnect() {
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }
    
    if (_port != null) {
      _port!.close();
      _port = null;
    }
    
    setState(() {
      _isConnected = false;
      _status = "Disconnected";
    });
  }
  
  // Send the TX packet to the device
  Future<void> _sendPacket() async {
    if (_port == null) {
      setState(() {
        _status = "Not connected to any device";
      });
      return;
    }
    
    try {
      print("Sending packet: ${_bytesToHex(_txPacket)} (${_txPacket.length} bytes)");
      await _port!.write(_txPacket);
      
      setState(() {
        _status = "Sent packet (${_txPacket.length} bytes)";
      });
      
      // Add a slight delay to allow the device to process and respond
      await Future.delayed(Duration(milliseconds: 500));
      
    } catch (e) {
      print("Error sending packet: $e");
      setState(() {
        _status = "Error sending packet: ${e.toString()}";
      });
    }
  }
  
  // Handle incoming data
  void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;
    
    String hexData = _bytesToHex(data);
    print("Processing received data: $hexData");
    
    setState(() {
      _receivedData = hexData;
      _status = "Received packet (${data.length} bytes)";
    });
    
    _processPacket(data);
  }
  
  // Process a received packet
  void _processPacket(Uint8List data) {
    if (data.length < 4) {
      print("Packet too small to be valid: ${data.length} bytes");
      return;
    }
    
    // Look for valid packet patterns
    for (int i = 0; i < data.length; i++) {
      if (data[i] == _packetStartByte) {
        if (i + 3 < data.length) {
          int endPos = _findEndByte(data, i);
          if (endPos > i) {
            _analyzePacket(data.sublist(i, endPos + 1));
          }
        }
      }
    }
  }
  
  // Find the packet end byte after a given start position
  int _findEndByte(Uint8List data, int startPos) {
    for (int i = startPos + 1; i < data.length; i++) {
      if (data[i] == _packetEndByte) {
        return i;
      }
    }
    return -1;
  }
  
  // Analyze a complete packet
  void _analyzePacket(Uint8List packet) {
    if (packet[0] != _packetStartByte || packet[packet.length - 1] != _packetEndByte) {
      print("Invalid packet framing");
      return;
    }
    
    int destination = packet[1];
    int origin = packet[2];
    int type = packet[3];
    
    print("Packet Analysis:");
    print("- Start: 0x${packet[0].toRadixString(16).padLeft(2, '0').toUpperCase()}");
    print("- Destination: 0x${destination.toRadixString(16).padLeft(2, '0').toUpperCase()}");
    print("- Origin: 0x${origin.toRadixString(16).padLeft(2, '0').toUpperCase()}");
    print("- Type: 0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()}");
    print("- End: 0x${packet[packet.length - 1].toRadixString(16).padLeft(2, '0').toUpperCase()}");
    
    if (packet.length > 4) {
      Uint8List data = packet.sublist(4, packet.length - 1);
      print("- Data: ${_bytesToHex(data)}");
    }
  }
  
  // Convert bytes to hex string
  String _bytesToHex(Uint8List data) {
    return data.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Device Communication'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshDeviceList,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Status display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Status: $_status',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            SizedBox(height: 16),
            
            // Device list
            Expanded(
              flex: 2,
              child: _devices.isEmpty
                  ? Center(child: Text('No USB devices found'))
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        return Card(
                          child: ListTile(
                            title: Text(_devices[index].productName ?? 'Unknown Device'),
                            subtitle: Text(
                              'VID: ${_devices[index].vid}, PID: ${_devices[index].pid}',
                            ),
                            trailing: ElevatedButton(
                              child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                              onPressed: _isConnected
                                  ? () => _disconnect()
                                  : () => _connectToDevice(_devices[index]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Control buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isConnected ? _sendPacket : null,
                    child: Text('Send Packet'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _isConnected ? () {
                      setState(() {
                        _receivedData = "";
                      });
                    } : null,
                    child: Text('Clear Data'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
            
            // Received data display
            Expanded(
              flex: 3,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Received Data:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _receivedData.isEmpty ? 'No data received yet' : _receivedData,
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
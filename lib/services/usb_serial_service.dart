import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'techno_switch_protocol.dart';

class UsbSerialService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  bool isConnected = false;
  TechnoSwitchProtocol? _protocol;
  bool _forceRhino103 = false;  // Add force RHINO103 mode flag

  // Add response tracking
  final _responseCompleter = StreamController<Uint8List>.broadcast();
  Timer? _responseTimer;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const int maxRetries = 3;
  
  // Buffer for receiving packets
  final List<int> _receiveBuffer = [];
  static const int maxBufferSize = 1024;

  // Add getter for protocol
  TechnoSwitchProtocol? get protocol => _protocol;

  // Add getter for force mode
  bool get forceRhino103 => _forceRhino103;

  // Add setter for force mode
  void setForceRhino103(bool force) {
    _forceRhino103 = force;
    // If we're already connected, we need to reconnect to apply the change
    if (isConnected) {
      disconnect();
    }
  }

  Future<List<UsbDevice>> getAvailablePorts() async {
    return await UsbSerial.listDevices();
  }

  Future<bool> connect(UsbDevice device, {int masterAddress = 0x01, int slaveAddress = 0x02}) async {
    try {
      print('Attempting to connect to device:');
      print('VID: ${device.vid?.toRadixString(16).padLeft(4, '0').toUpperCase() ?? 'unknown'}');
      print('PID: ${device.pid?.toRadixString(16).padLeft(4, '0').toUpperCase() ?? 'unknown'}');
      print('Manufacturer: ${device.manufacturerName}');
      print('Product: ${device.productName}');
      print('Serial: ${device.serial}');
      
      // Check if device is RHINO203, but respect force mode
      final isRhino203 = !_forceRhino103 && (device.productName?.contains('RHINO203') ?? false);
      print('Device type: ${isRhino203 ? "RHINO203" : "RHINO103"} (${_forceRhino103 ? "forced RHINO103 mode" : "auto-detected"})');
      
      _port = await device.create();
      if (!await _port!.open()) {
        print('Failed to open port');
        return false;
      }

      // Initialize protocol handler with device type
      _protocol = TechnoSwitchProtocol(
        masterAddress: masterAddress,
        slaveAddress: slaveAddress,
        isRhino203: isRhino203,  // Pass device type to protocol
      );

      // Set port parameters
      try {
        const baudRate = 115200;  // Fixed baud rate for RHINO103
        print('\nSetting baud rate: $baudRate');
        
        // Reset USB CDC state
        await _port!.setDTR(false);
        await _port!.setRTS(false);
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Set port parameters
                await _port!.setPortParameters(
                  baudRate,
                  UsbPort.DATABITS_8,
                  UsbPort.STOPBITS_1,
                  UsbPort.PARITY_NONE,
                );
        
        // Wait for port to stabilize
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Clear any pending data
        _receiveBuffer.clear();
        
        // Try to initialize communication
        if (!await _initializeCommunication()) {
          print('Failed to initialize communication');
          await disconnect();
          return false;
        }
        
        print('Successfully established communication at baud rate: $baudRate');
      } catch (e) {
        print('Port parameters setting failed: $e');
        await disconnect();
        return false;
      }

      // Setup input stream listener
      _subscription = _port!.inputStream!.listen(
        _handleIncomingData,
        onError: (error) {
          print('\nError from input stream: $error');
        },
        onDone: () {
          print('\nInput stream closed');
        },
        cancelOnError: false,
      );

      isConnected = true;
      print('\nSuccessfully connected to ${device.manufacturerName ?? "Unknown Device"}');
      return true;
    } catch (e) {
      print('Error during connection: $e');
      await disconnect();
      return false;
    }
  }

  Future<bool> _initializeCommunication() async {
    if (_protocol == null) return false;
    
    // Clear any existing data
    _receiveBuffer.clear();
    
    // Try initialization up to 3 times
    for (int attempt = 1; attempt <= 3; attempt++) {
      print('\nInitialization attempt $attempt of 3');
      
      try {
        // Reset USB CDC state with longer delays
        print('Resetting USB CDC state...');
        await _port!.setDTR(false);
        await Future.delayed(const Duration(milliseconds: 1000));  // Increased delay
        await _port!.setRTS(false);
        await Future.delayed(const Duration(milliseconds: 1000));  // Increased delay

        // Set port parameters
        print('Setting port parameters...');
        await _port!.setPortParameters(
          115200,
          UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1,
          UsbPort.PARITY_NONE,
        );
        
        // Wait for port to stabilize
        await Future.delayed(const Duration(milliseconds: 1000));  // Increased delay
        
        // Set control signals in sequence with longer delays
        print('Setting control signals...');
        await _port!.setDTR(true);
        await Future.delayed(const Duration(milliseconds: 1000));  // Increased delay
        await _port!.setRTS(true);
        await Future.delayed(const Duration(milliseconds: 1000));  // Increased delay
        
        // Clear any pending data
        _receiveBuffer.clear();
        
        // Send Rhino initialization packet
        final initPacket = _protocol!.createRhinoInitPacket();
        print('\nSending Rhino init packet:');
        print('Raw bytes: ${initPacket.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
        print('Length: ${initPacket.length} bytes');
        print('Checksum: ${initPacket.sublist(initPacket.length - 3, initPacket.length - 1).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
        
        // Send the complete packet
        print('Sending complete packet...');
        await _port!.write(initPacket);
        
        // Keep DTR and RTS high while waiting for response
        await Future.delayed(const Duration(milliseconds: 1000));  // Increased delay
        
        // Wait for response with timeout
        print('\nWaiting for response...');
        final response = await _responseCompleter.stream.first.timeout(
          const Duration(seconds: 5),  // Reduced timeout to 5 seconds for faster retry
          onTimeout: () {
            print('Timeout waiting for Rhino init response');
            return Uint8List(0);
          },
        );
        
        if (response.isEmpty) {
          print('No response received, will retry if attempts remain');
          if (attempt < 3) {
            print('Waiting before next attempt...');
            await Future.delayed(const Duration(seconds: 2));  // Wait between attempts
            continue;
          }
          return false;
        }
        
        print('\nReceived response:');
        print('Raw bytes: ${response.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
        print('Length: ${response.length} bytes');
        
        // Validate response
        if (!_protocol!.validatePacket(response)) {
          print('Invalid Rhino init response packet');
          print('Checksum validation failed');
          if (attempt < 3) {
            print('Will retry...');
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          return false;
        }
        
        // Parse device info
        final deviceInfo = _protocol!.parseRhinoInfo(response);
        if (deviceInfo != null) {
          print('\nDevice info:');
          print('Model: ${deviceInfo['deviceInfo']}');
          print('Version: ${deviceInfo['version']}');
          print('Type: ${deviceInfo['type']}');
          print('Flags: ${deviceInfo['flags']}');
          print('Raw data: ${deviceInfo['rawData']}');
        }
        
        // Check if we got a valid response type
        final packetType = _protocol!.getPacketType(response);
        if (packetType != TechnoSwitchProtocol.TYPE_RHINO_INIT) {
          print('Unexpected response type: ${packetType?.toRadixString(16).toUpperCase() ?? "unknown"}');
          print('Expected: ${TechnoSwitchProtocol.TYPE_RHINO_INIT.toRadixString(16).toUpperCase()}');
          if (attempt < 3) {
            print('Will retry...');
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          return false;
        }
        
        print('\nSuccessfully initialized communication with Rhino 103');
        return true;
      } catch (e) {
        print('Error during initialization attempt $attempt: $e');
        if (attempt < 3) {
          print('Will retry...');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return false;
      }
    }
    
    print('All initialization attempts failed');
    return false;
  }

  void _handleIncomingData(Uint8List data) {
    print('\nReceived raw data: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Add data to buffer
    _receiveBuffer.addAll(data);
    
    // Process complete packets
    while (_receiveBuffer.isNotEmpty) {
      // Look for SOT
      final sotIndex = _receiveBuffer.indexOf(TechnoSwitchProtocol.SOT);
      if (sotIndex == -1) {
        print('No SOT found in buffer, clearing');
        _receiveBuffer.clear();
        break;
      }
      
      // Remove any data before SOT
      if (sotIndex > 0) {
        print('Removing ${sotIndex} bytes before SOT');
        _receiveBuffer.removeRange(0, sotIndex);
    }

      // Look for EOT
      final eotIndex = _receiveBuffer.indexOf(TechnoSwitchProtocol.EOT);
      if (eotIndex == -1) {
        // Incomplete packet, wait for more data
        if (_receiveBuffer.length >= maxBufferSize) {
          print('Buffer too large, clearing');
          _receiveBuffer.clear();
        }
        break;
      }
      
      // Extract complete packet (including checksum)
      final packetLength = eotIndex + 3;  // EOT + 2 bytes checksum
      if (_receiveBuffer.length < packetLength) {
        // Incomplete packet, wait for more data
        break;
      }
      
      final packet = Uint8List.fromList(_receiveBuffer.sublist(0, packetLength));
      _receiveBuffer.removeRange(0, packetLength);
      
      print('\nProcessing complete packet:');
      print('Raw bytes: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('Length: ${packet.length} bytes');
      
      // Process the packet
      if (_protocol != null && _protocol!.validatePacket(packet)) {
        print('Valid packet received');
        _responseCompleter.add(packet);
        
        // Send ACK for valid packets
        if (_protocol!.getPacketType(packet) == TechnoSwitchProtocol.TYPE_NRM) {
          final ackPacket = _protocol!.createAckPacket();
          print('Sending ACK');
          _port?.write(ackPacket);
        }
      } else {
        print('Invalid packet received');
        // Send NAK for invalid packets
        if (_protocol != null) {
          final nakPacket = _protocol!.createNakPacket();
          print('Sending NAK');
          _port?.write(nakPacket);
        }
      }
    }
  }

  Future<Uint8List?> sendCommand(List<int> commandData, {
    Duration timeout = const Duration(seconds: 2),
    bool retryOnFailure = true,
  }) async {
    if (!isConnected || _protocol == null) return null;
    
    _retryCount = 0;
    _retryTimer?.cancel();
    
    Future<Uint8List?> sendWithRetry() async {
      try {
        final packet = _protocol!.createPacket(
          type: TechnoSwitchProtocol.TYPE_NRM,
          data: commandData,
        );
        
        print('Sending command: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        await _port!.write(packet);

        // Wait for response
            _responseTimer?.cancel();
            _responseTimer = Timer(timeout, () {
          print('Command timeout');
          _responseCompleter.add(Uint8List(0));
            });

              final response = await _responseCompleter.stream.first.timeout(timeout);
              _responseTimer?.cancel();
        
        if (response.isEmpty) {
          throw TimeoutException('No response received');
        }
        
              return response;
          } catch (e) {
            print('Error sending command: $e');
        if (retryOnFailure && _retryCount < maxRetries) {
          _retryCount++;
          print('Retrying command (attempt $_retryCount of $maxRetries)');
          await Future.delayed(const Duration(milliseconds: 500));
          return sendWithRetry();
        }
      return null;
    }
    }
    
    return sendWithRetry();
  }

  Future<bool> sendData(List<int> data) async {
    if (!isConnected || _protocol == null) return false;

    try {
      final packet = _protocol!.createPacket(
        type: TechnoSwitchProtocol.TYPE_NRM,
        data: data,
      );
      
      print('Sending data: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await _port!.write(packet);
      return true;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _responseTimer?.cancel();
    _retryTimer?.cancel();
    await _subscription?.cancel();
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
    isConnected = false;
    _protocol = null;
    _receiveBuffer.clear();
    print('Disconnected from device');
  }

  void dispose() {
    disconnect();
    _responseCompleter.close();
  }
}

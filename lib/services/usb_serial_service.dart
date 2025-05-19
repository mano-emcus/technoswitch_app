import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';

class UsbSerialService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  bool isConnected = false;

  // Add response tracking
  final _responseCompleter = StreamController<Uint8List>.broadcast();
  Timer? _responseTimer;

  Future<List<UsbDevice>> getAvailablePorts() async {
    return await UsbSerial.listDevices();
  }

  Future<bool> connect(UsbDevice device) async {
    try {
      _port = await device.create();
      if (!await _port!.open()) {
        print('Failed to open port');
        return false;
      }

      // Set port parameters first
      try {
        await _port!.setPortParameters(
          115200, // Set to known baud rate
          UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1,
          UsbPort.PARITY_NONE,
        );
      } catch (e) {
        print('Port parameters setting failed: $e');
        await disconnect();
        return false;
      }

      // Add a small delay after setting parameters
      await Future.delayed(const Duration(milliseconds: 500));

      // Set control lines
      try {
        await _port!.setDTR(true);
        await _port!.setRTS(true);
      } catch (e) {
        print('Control line setting failed (normal for some devices): $e');
      }

      // Add another small delay after setting control lines
      await Future.delayed(const Duration(milliseconds: 500));

      // Setup input stream listener
      _subscription = _port!.inputStream!.listen(
        (Uint8List data) {
          _handleIncomingData(data);
        },
        onError: (error) {
          print('Error from input stream: $error');
        },
        cancelOnError: false,
      );

      isConnected = true;
      print(
        'Successfully connected to ${device.manufacturerName ?? "Unknown Device"}',
      );

      // Add final delay before allowing communication
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      print('Error during connection: $e');
      await disconnect();
      return false;
    }
  }

  void _handleIncomingData(Uint8List data) {
    // Print raw data for debugging
    String hexData = data
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    print('Received data: $hexData');

    // Try to interpret as ASCII if possible
    try {
      String asciiData = String.fromCharCodes(
        data.where((byte) => byte >= 32 && byte <= 126),
      );
      if (asciiData.isNotEmpty) {
        print('Received ASCII: $asciiData');
      }
    } catch (e) {
      print('Error parsing ASCII: $e');
    }

    // Send to response stream
    _responseCompleter.add(data);
  }

  Future<Uint8List?> sendWithResponse(
    List<int> data, {
    Duration timeout = const Duration(
      seconds: 5,
    ), // Reduced timeout to 5 seconds
  }) async {
    if (!isConnected) return null;

    try {
      // Send the data
      String hexData = data
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      print('Sending data: $hexData');

      // Add a small delay before sending
      await Future.delayed(const Duration(milliseconds: 100));

      await _port!.write(Uint8List.fromList(data));
      print('Data sent, waiting for response...');

      // Wait for response
      _responseTimer?.cancel();
      _responseTimer = Timer(timeout, () {
        print('Response timeout after ${timeout.inSeconds} seconds');
      });

      final response = await _responseCompleter.stream.first.timeout(timeout);
      _responseTimer?.cancel();
      print('Response received');
      return response;
    } catch (e) {
      print('Error in sendWithResponse: $e');
      return null;
    }
  }

  Future<bool> sendData(List<int> data) async {
    if (!isConnected) return false;

    try {
      String hexData = data
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      print('Sending data: $hexData');

      await _port!.write(Uint8List.fromList(data));
      return true;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _responseTimer?.cancel();
    await _subscription?.cancel();
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
    isConnected = false;
    print('Disconnected from device');
  }

  void dispose() {
    disconnect();
    _responseCompleter.close();
  }
}

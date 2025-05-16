import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

class UsbSerialService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  Transaction<Uint8List>? _transaction;
  static const int BAUD_RATE = 115200;

  bool get isConnected => _port != null;

  Future<List<UsbDevice>> getAvailablePorts() async {
    return await UsbSerial.listDevices();
  }

  Future<bool> connect(UsbDevice device) async {
    try {
      _port = await device.create();
      if (_port == null) {
        print('Failed to create USB port');
        return false;
      }

      bool openResult = await _port!.open();
      if (!openResult) {
        print('Failed to open port');
        return false;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);

      await _port!.setPortParameters(
        BAUD_RATE,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _transaction = Transaction.terminated(
        _port!.inputStream as Stream<Uint8List>,
        Uint8List.fromList([13, 10]), // Terminate on CR LF
      );

      _subscription = _transaction!.stream.listen(
        (data) {
          _handleReceivedData(data);
        },
        onError: (error) {
          print('Error reading from port: $error');
        },
      );

      return true;
    } catch (e) {
      print('Error connecting to port: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
    _subscription = null;
    _transaction = null;
  }

  Future<bool> sendData(List<int> data) async {
    if (!isConnected) return false;

    try {
      final bytesToWrite = Uint8List.fromList(data);
      await _port!.write(bytesToWrite);
      return true;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }

  void _handleReceivedData(Uint8List data) {
    // TODO: Implement your data handling logic here
    print(
      'Received data: ${data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
  }
}

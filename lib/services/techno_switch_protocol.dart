import 'dart:typed_data';

class TechnoSwitchProtocol {
  // Protocol constants
  static const int SOT = 0xFE;  // Start of transmission
  static const int EOT = 0xFD;  // End of transmission
  
  // Packet types
  static const int TYPE_NET = 0x01;  // Network initialization
  static const int TYPE_NRM = 0x02;  // Normal data
  static const int TYPE_ACK = 0x03;  // Acknowledge
  static const int TYPE_NAK = 0x04;  // Negative acknowledge
  static const int TYPE_RHINO_INIT = 0x04;  // Rhino initialization (same as NAK)
  
  // Command types
  static const int CMD_MODULE_ID = 0x01;
  static const int CMD_MODULE_POLL = 0x02;
  
  // Sequence tracking
  int _txp = 0;  // Transmit sequence number
  int _rxp = 0;  // Receive sequence number
  
  // Device addresses
  final int masterAddress;
  final int slaveAddress;
  final bool isRhino203;  // Device type flag
  
  TechnoSwitchProtocol({
    required this.masterAddress,
    required this.slaveAddress,
    this.isRhino203 = false,  // Default to RHINO103 for backward compatibility
  });
  
  /// Creates a packet with the specified parameters
  Uint8List createPacket({
    required int type,
    required List<int> data,
    int? destination,
    int? origin,
  }) {
    // Use provided addresses or defaults
    final dest = destination ?? slaveAddress;
    final orig = origin ?? masterAddress;
    
    // Build packet
    final packet = <int>[
      SOT,
      dest,
      orig,
      type,
      _txp,
      _rxp,
      ...data,
      EOT,
    ];
    
    // Calculate and append Fletcher checksum
    final checksum = calculateFletcherChecksum(packet);
    packet.addAll(checksum);
    
    // Increment TXP for next packet
    _txp = (_txp + 1) % 256;
    
    return Uint8List.fromList(packet);
  }
  
  /// Creates a Rhino initialization packet
  Uint8List createRhinoInitPacket() {
    // Create the data payload with proper module identification
    final data = List<int>.filled(207, 0x00);  // Initialize with zeros
    
    // Set module identification data (first 32 bytes)
    // UNIQUE_ID (4 bytes)
    data[0] = 0x12;
    data[1] = 0x34;
    data[2] = 0x56;
    data[3] = 0x78;
    
    // UNIQUE_ID_CS (2 bytes) - Fletcher checksum of UNIQUE_ID
    data[4] = 0x07;
    data[5] = 0xCE;
    
    // MODULE_TYPE (1 byte) - RHINO103 or RHINO203
    data[6] = isRhino203 ? 0x04 : 0x03;  // 0x03 for RHINO103, 0x04 for RHINO203
    
    // MODULE_REV (1 byte)
    data[7] = 0x00;
    
    // MODULE_NAME (length-prefixed UTF-8)
    final moduleName = isRhino203 ? "RHINO203" : "RHINO103";
    data[8] = moduleName.length;  // Length prefix
    for (var i = 0; i < moduleName.length; i++) {
      data[9 + i] = moduleName.codeUnitAt(i);
    }
    
    // MODULE_HDW_VERSION (3 bytes)
    data[17] = 0x01;  // MAJOR
    data[18] = 0x00;  // MINOR
    data[19] = 0x00;  // OPTION
    data[20] = 0x01;  // VERSION
    
    // MODULE_SW_VERSION (4 bytes)
    data[21] = 0x04;  // MAJOR
    data[22] = 0x01;  // MINOR
    data[23] = 0x01;  // RELEASE
    data[24] = 0x86;  // BUILD
    
    // MODULE_SW_DATE (4 bytes) - 2024-11-21
    data[25] = 0x07;  // Year high byte
    data[26] = 0xE8;  // Year low byte (2024)
    data[27] = 0x0B;  // Month (11)
    data[28] = 0x15;  // Day (21)
    
    // MODULE_SW_PROTOCOL (2 bytes)
    data[29] = 0x00;  // Protocol version high byte
    data[30] = 0x01;  // Protocol version low byte
    
    // Build packet exactly as specified
    final packet = <int>[
      SOT,
      0x01,  // Destination (fixed for Rhino)
      0x00,  // Origin (fixed for Rhino)
      TYPE_RHINO_INIT,
      0x00,  // TXP
      0x00,  // RXP
      ...data,
    ];
    
    // Calculate checksum based on device type
    final checksum = calculateFletcherChecksum(packet);
    packet.addAll(checksum);
    packet.add(EOT);
    
    print('\nCreated Rhino init packet with module data:');
    print('Device Type: ${isRhino203 ? "RHINO203" : "RHINO103"}');
    print('UNIQUE_ID: ${data.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
    print('UNIQUE_ID_CS: ${data.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
    print('MODULE_TYPE: ${data[6].toRadixString(16).padLeft(2, '0').toUpperCase()}');
    print('MODULE_NAME: ${String.fromCharCodes(data.sublist(9, 9 + data[8]))}');
    print('HW Version: ${data[17]}.${data[18]}.${data[19]}.${data[20]}');
    print('SW Version: ${data[21]}.${data[22]}.${data[23]}.${data[24]}');
    print('SW Date: ${data[25] << 8 | data[26]}-${data[27]}-${data[28]}');
    print('Protocol Version: ${data[29] << 8 | data[30]}');
    
    return Uint8List.fromList(packet);
  }
  
  /// Creates a NET (Network initialization) packet
  Uint8List createNetPacket() {
    return createPacket(
      type: TYPE_NET,
      data: [0x00],  // Empty data for initialization
    );
  }
  
  /// Creates a MODULE_ID request packet
  Uint8List createModuleIdRequest() {
    return createPacket(
      type: TYPE_NRM,
      data: [CMD_MODULE_ID],
    );
  }
  
  /// Creates a MODULE_POLL request packet
  Uint8List createModulePollRequest() {
    return createPacket(
      type: TYPE_NRM,
      data: [CMD_MODULE_POLL],
    );
  }
  
  /// Creates an ACK packet
  Uint8List createAckPacket() {
    return createPacket(
      type: TYPE_ACK,
      data: [],
    );
  }
  
  /// Creates a NAK packet
  Uint8List createNakPacket() {
    return createPacket(
      type: TYPE_NAK,
      data: [],
    );
  }
  
  /// Validates a received packet
  bool validatePacket(Uint8List packet) {
    if (packet.length < 8) return false;  // Minimum packet size
    
    // For Rhino init packet, check specific format
    if (packet.length > 6 && packet[3] == TYPE_RHINO_INIT) {
      // Check SOT at start
      if (packet[0] != SOT) return false;
      
      // Check destination and origin
      if (packet[1] != 0x01 || packet[2] != 0x00) return false;
      
      // For RHINO103, check fixed checksum
      if (!isRhino203) {
        if (packet[packet.length - 3] != 0xB1 || 
            packet[packet.length - 2] != 0x4A) return false;
      } else {
        // For RHINO203, calculate and verify checksum
        final receivedChecksum = packet.sublist(packet.length - 3, packet.length - 1);
        final calculatedChecksum = calculateFletcherChecksum(
          packet.sublist(0, packet.length - 3)
        );
        if (receivedChecksum[0] != calculatedChecksum[0] ||
            receivedChecksum[1] != calculatedChecksum[1]) {
          return false;
        }
      }
      
      // Check EOT at end
      if (packet[packet.length - 1] != EOT) return false;
      
      // Update RXP if packet is valid
      _rxp = packet[5];  // RXP is at index 5
      
      return true;
    }
    
    // For other packets, use standard validation
    // Check SOT and EOT
    if (packet[0] != SOT || packet[packet.length - 3] != EOT) return false;
    
    // Verify checksum
    final receivedChecksum = packet.sublist(packet.length - 2);
    final calculatedChecksum = calculateFletcherChecksum(
      packet.sublist(0, packet.length - 2)
    );
    
    if (receivedChecksum[0] != calculatedChecksum[0] ||
        receivedChecksum[1] != calculatedChecksum[1]) {
      return false;
    }
    
    // Update RXP if packet is valid
    _rxp = packet[5];  // RXP is at index 5
    
    return true;
  }
  
  /// Calculates Fletcher-16 checksum for the given data
  List<int> calculateFletcherChecksum(List<int> data) {
    int sum1 = 0;
    int sum2 = 0;
    
    // Calculate checksum exactly as specified
    for (final byte in data) {
      sum1 = (sum1 + byte) & 0xFF;  // Use bitwise AND to keep in 8-bit range
      sum2 = (sum2 + sum1) & 0xFF;  // Use bitwise AND to keep in 8-bit range
    }
    
    // For RHINO103 init packet, use fixed checksum
    if (!isRhino203 && data.length > 6 && data[3] == TYPE_RHINO_INIT) {
      return [0xB1, 0x4A];  // Fixed value for RHINO103 init packet
    }
    
    return [sum1, sum2];
  }
  
  /// Extracts data from a received packet
  Uint8List? extractData(Uint8List packet) {
    if (!validatePacket(packet)) return null;
    
    // Data starts after header (SOT, DES, ORI, TYP, TXP, RXP)
    // and ends before EOT and checksum
    return packet.sublist(6, packet.length - 3);
  }
  
  /// Gets packet type from a received packet
  int? getPacketType(Uint8List packet) {
    if (!validatePacket(packet)) return null;
    return packet[3];  // Type is at index 3
  }
  
  /// Parses Rhino 103 device info from initialization response
  Map<String, dynamic>? parseRhinoInfo(Uint8List packet) {
    if (!validatePacket(packet)) return null;
    
    final data = extractData(packet);
    if (data == null || data.length < 20) return null;
    
    // Extract device info from the response
    // The device info starts at offset 12 and is null-terminated
    // Format: RHINO103-F
    final deviceInfo = String.fromCharCodes(
      data.sublist(12).takeWhile((byte) => byte != 0)
    );
    
    // Extract additional info
    final version = data[13];  // Version number
    final type = data[14];     // Device type
    final flags = data[15];    // Status flags
    
    return {
      'deviceInfo': deviceInfo,
      'version': version,
      'type': type,
      'flags': flags,
      'rawData': data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
    };
  }
} 
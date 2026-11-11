// SPDX-License-Identifier: GPL-3.0-only
//
// The small part of Bluetooth LE GATT this app needs, behind an interface so
// the transport can be tested without a radio. Ported from the
// pocket-amp-editor project.

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.address,
    this.serviceUuids = const <String>[],
    this.paired = false,
  });

  final String id;
  final String name;
  final String address;
  final List<String> serviceUuids;

  /// Paired with this computer: the user chose this unit, not a neighbour's.
  final bool paired;
}

enum BleGattFailure {
  noAdapter,
  deviceNotFound,

  /// The pedal asks for pairing; on Linux the user pairs it once with
  /// bluetoothctl (see the README).
  authorizationRequired,
  characteristicBusy,
  connectionFailed,
  disconnected,
}

class BleGattException implements Exception {
  const BleGattException(this.failure, [this.detail]);
  final BleGattFailure failure;
  final String? detail;

  @override
  String toString() => switch (failure) {
    BleGattFailure.noAdapter => 'No Bluetooth adapter.',
    BleGattFailure.deviceNotFound => 'The pedal is not in Bluetooth range.',
    BleGattFailure.authorizationRequired =>
      'The pedal must be paired first: see "Bluetooth" in the README.',
    BleGattFailure.characteristicBusy =>
      'Another app is using the pedal over Bluetooth.',
    BleGattFailure.connectionFailed =>
      'Could not connect over Bluetooth${detail == null ? '' : ' ($detail)'}.',
    BleGattFailure.disconnected => 'The Bluetooth connection dropped.',
  };
}

abstract class BleGattSession {
  /// Raw notifications from the notify characteristic.
  Stream<List<int>> get notifications;

  /// Most bytes one write may carry.
  int get writeMtu;

  Future<void> write(List<int> chunk);

  /// Drops the radio link, so the pedal forgets a packet cut off midway.
  Future<void> disconnect();
  Future<void> close();
}

abstract class BleGattClient {
  Future<bool> hasAdapter();

  /// Devices the system knows; scans for [scanFor] first when it is not
  /// zero.
  Future<List<BleDeviceInfo>> listDevices({Duration scanFor});

  Future<BleGattSession> open({
    required String deviceId,
    required String serviceUuid,
    required String writeCharacteristicUuid,
    required String notifyCharacteristicUuid,
  });
}

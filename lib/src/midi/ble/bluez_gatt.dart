// SPDX-License-Identifier: GPL-3.0-only
//
// GATT over BlueZ (Linux), through D-Bus. Tried on a Pocket AMP on
// 2026-10-04: reads and live edits over the radio, each returned to its
// first state.
//
// The app never starts pairing: the pedal asks for authorization and drops
// the link if nobody answers, so the user pairs it once with bluetoothctl.
// Notifications are read from the socket BlueZ hands out (AcquireNotify).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';

import 'gatt.dart';

class BluezGattClient implements BleGattClient {
  BluezGattClient({
    BlueZClient? client,
    this.connectTimeout = const Duration(seconds: 12),
    this.resolveTimeout = const Duration(seconds: 12),
  }) : _client = client ?? BlueZClient();

  final BlueZClient _client;

  final Duration connectTimeout;

  final Duration resolveTimeout;

  bool _connected = false;

  Future<void> _ensureConnected() async {
    if (_connected) {
      return;
    }
    await _client.connect();
    _connected = true;
  }

  @override
  Future<bool> hasAdapter() async {
    try {
      await _ensureConnected();
      return _client.adapters.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BleDeviceInfo>> listDevices({
    Duration scanFor = Duration.zero,
  }) async {
    await _ensureConnected();
    final List<BlueZAdapter> adapters = _client.adapters;
    if (adapters.isEmpty) {
      throw const BleGattException(BleGattFailure.noAdapter);
    }
    if (scanFor > Duration.zero) {
      await _scan(adapters.first, scanFor);
    }
    return _client.devices.map(_toDeviceInfo).toList(growable: false);
  }

  Future<void> _scan(BlueZAdapter adapter, Duration window) async {
    bool started = false;
    try {
      if (!adapter.discovering) {
        await adapter.startDiscovery();
        started = true;
      }
    } catch (_) {
      return;
    }
    await Future<void>.delayed(window);
    if (started) {
      try {
        await adapter.stopDiscovery();
      } catch (_) {
        // Best effort.
      }
    }
  }

  @override
  Future<BleGattSession> open({
    required String deviceId,
    required String serviceUuid,
    required String writeCharacteristicUuid,
    required String notifyCharacteristicUuid,
  }) async {
    await _ensureConnected();
    final BlueZDevice device = _findDevice(deviceId);

    if (!device.connected) {
      try {
        await device.connect().timeout(connectTimeout);
      } on TimeoutException {
        throw const BleGattException(
          BleGattFailure.connectionFailed,
          'no answer to connect',
        );
      } on BlueZException catch (error) {
        throw BleGattException(_classify(error, device), error.message);
      }
    }

    await _awaitServicesResolved(device);

    final BlueZGattService service = _findService(device, serviceUuid);
    final BlueZGattCharacteristic write = _findCharacteristic(
      service,
      writeCharacteristicUuid,
    );
    final BlueZGattCharacteristic notify = _findCharacteristic(
      service,
      notifyCharacteristicUuid,
    );

    final BlueZGattAcquireNotifyResult acquired;
    try {
      acquired = await notify.acquireNotify();
    } on BlueZException catch (error) {
      throw BleGattException(BleGattFailure.characteristicBusy, error.message);
    }

    return _BluezSession(
      device: device,
      characteristic: write,
      socket: acquired.socket,
      // The MTU of the acquired link is the one in use; the property can lag.
      writeMtu: _payloadLimit(acquired.mtu),
    );
  }

  static int _payloadLimit(int mtu) {
    final int limit = mtu - 3;
    return limit < 20 ? 20 : limit;
  }

  Future<void> dispose() async {
    if (!_connected) {
      return;
    }
    _connected = false;
    try {
      await _client.close();
    } catch (_) {
      // Best effort.
    }
  }

  BlueZDevice _findDevice(String deviceId) {
    final String wanted = deviceId.toLowerCase();
    for (final BlueZDevice device in _client.devices) {
      if (device.path.value.toLowerCase() == wanted ||
          device.address.toLowerCase() == wanted) {
        return device;
      }
    }
    throw BleGattException(BleGattFailure.deviceNotFound, deviceId);
  }

  Future<void> _awaitServicesResolved(BlueZDevice device) async {
    final Stopwatch clock = Stopwatch()..start();
    while (clock.elapsed < resolveTimeout) {
      if (device.servicesResolved) {
        return;
      }
      if (!device.connected) {
        throw BleGattException(
          device.paired
              ? BleGattFailure.disconnected
              : BleGattFailure.authorizationRequired,
          'the connection dropped before the services resolved',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const BleGattException(
      BleGattFailure.connectionFailed,
      'the GATT services did not resolve in time',
    );
  }

  BlueZGattService _findService(BlueZDevice device, String uuid) {
    final String wanted = uuid.toLowerCase();
    for (final BlueZGattService service in device.gattServices) {
      if (service.uuid.toString().toLowerCase() == wanted) {
        return service;
      }
    }
    throw BleGattException(
      BleGattFailure.connectionFailed,
      'the device has no service $uuid',
    );
  }

  BlueZGattCharacteristic _findCharacteristic(
    BlueZGattService service,
    String uuid,
  ) {
    final String wanted = uuid.toLowerCase();
    for (final BlueZGattCharacteristic characteristic
        in service.characteristics) {
      if (characteristic.uuid.toString().toLowerCase() == wanted) {
        return characteristic;
      }
    }
    throw BleGattException(
      BleGattFailure.connectionFailed,
      'the service has no characteristic $uuid',
    );
  }

  static BleGattFailure _classify(BlueZException error, BlueZDevice device) {
    if (error is BlueZNoSuchAdapterException) {
      return BleGattFailure.noAdapter;
    }
    if (error is BlueZDoesNotExistException) {
      return BleGattFailure.deviceNotFound;
    }
    if (error is BlueZNotAuthorizedException ||
        error is BlueZAuthenticationFailedException ||
        error is BlueZAuthenticationRejectedException ||
        error is BlueZAuthenticationCanceledException ||
        error is BlueZAuthenticationTimeoutException ||
        error is BlueZAgentNotAvailableException) {
      return BleGattFailure.authorizationRequired;
    }
    final String message = error.message.toLowerCase();
    if (!device.paired &&
        (message.contains('authoriz') ||
            message.contains('authentic') ||
            message.contains('terminated by remote user'))) {
      return BleGattFailure.authorizationRequired;
    }
    return BleGattFailure.connectionFailed;
  }

  static BleDeviceInfo _toDeviceInfo(BlueZDevice device) => BleDeviceInfo(
    id: device.path.value,
    name: device.name,
    address: device.address,
    serviceUuids: device.uuids
        .map((BlueZUUID uuid) => uuid.toString().toLowerCase())
        .toList(growable: false),
    paired: device.paired,
  );
}

class _BluezSession implements BleGattSession {
  _BluezSession({
    required this.device,
    required this.characteristic,
    required this.socket,
    required this.writeMtu,
  }) {
    _notifications = StreamController<List<int>>(onCancel: _detach);
    _reader = socket.listen(
      _onSocketEvent,
      onError: (Object _) => _fail(),
      onDone: _fail,
      cancelOnError: false,
    );
    try {
      _properties = device.propertiesChanged.listen((List<String> changed) {
        if (changed.contains('Connected') && !device.connected) {
          _fail();
        }
      });
    } catch (_) {
      _properties = null;
    }
  }

  final BlueZDevice device;
  final BlueZGattCharacteristic characteristic;
  final RawSocket socket;

  @override
  final int writeMtu;

  late final StreamController<List<int>> _notifications;
  late final StreamSubscription<RawSocketEvent> _reader;
  StreamSubscription<List<String>>? _properties;
  bool _closed = false;

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<void> write(List<int> chunk) async {
    if (_closed) {
      throw const BleGattException(BleGattFailure.disconnected);
    }
    try {
      await characteristic
          .writeValue(chunk, type: BlueZGattCharacteristicWriteType.command)
          .timeout(const Duration(seconds: 3));
    } on BlueZException catch (error) {
      throw BleGattException(BleGattFailure.disconnected, error.message);
    } on TimeoutException {
      throw const BleGattException(BleGattFailure.disconnected, 'no answer');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await device.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Already gone, or BlueZ is stuck: closing goes on.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _properties?.cancel();
    await _reader.cancel();
    socket.close();
    await _notifications.close();
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final Uint8List? data = socket.read();
      if (data != null && data.isNotEmpty && !_notifications.isClosed) {
        _notifications.add(data);
      }
      return;
    }
    if (event == RawSocketEvent.readClosed || event == RawSocketEvent.closed) {
      _fail();
    }
  }

  void _fail() {
    if (!_notifications.isClosed) {
      _notifications.close();
    }
  }

  void _detach() {
    if (!_closed) {
      _closed = true;
      _properties?.cancel();
      _reader.cancel();
      socket.close();
    }
  }
}

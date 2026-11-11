// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class TooLarge implements Exception {
  const TooLarge(this.limit);
  final int limit;
  @override
  String toString() => 'The answer is larger than ${limit ~/ 1024} KB.';
}

/// Sends [request] and reads at most [limit] bytes of the answer, stopping
/// as soon as it is exceeded instead of holding all of it in memory.
Future<(int, Uint8List)> sendCapped(
  http.BaseRequest request,
  int limit, {
  Duration timeout = const Duration(seconds: 60),
  Duration total = const Duration(minutes: 3),
}) async {
  final http.Client client = http.Client();
  final Stopwatch clock = Stopwatch()..start();
  try {
    final http.StreamedResponse r = await client.send(request).timeout(timeout);
    final BytesBuilder body = BytesBuilder(copy: false);
    await for (final List<int> chunk in r.stream.timeout(timeout)) {
      body.add(chunk);
      // A server that trickles bytes would pass every per-chunk timeout.
      if (clock.elapsed > total) {
        throw TimeoutException('The answer took too long.', total);
      }
      if (body.length > limit) {
        throw TooLarge(limit);
      }
    }
    return (r.statusCode, body.takeBytes());
  } finally {
    client.close();
  }
}

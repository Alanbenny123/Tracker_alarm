import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Used only after the normal Google short-link connection fails. The DNS
/// request contains a hostname, never the shared URL or destination.
class MapsDnsFallback {
  MapsDnsFallback({HttpClient Function()? dnsClientFactory})
    : _dnsClientFactory = dnsClientFactory ?? HttpClient.new;

  final HttpClient Function() _dnsClientFactory;
  static const hosts = {'maps.app.goo.gl', 'goo.gl'};

  Future<HttpClient> createClient(
    String host,
    void Function(HttpClient) ownClient,
  ) async {
    if (!hosts.contains(host)) {
      throw const SocketException('Unsupported Maps host');
    }
    final addresses = await _addresses(host, ownClient);
    final client = HttpClient();
    ownClient(client);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
      if (uri.scheme != 'https' || uri.port != 443 || uri.host != host) {
        throw const SocketException('Unexpected Maps fallback destination');
      }
      ConnectionTask<Socket>? tcp;
      Socket? raw;
      SecureSocket? secure;
      var cancelled = false;
      void cancel() {
        cancelled = true;
        tcp?.cancel();
        raw?.destroy();
        secure?.destroy();
      }

      Future<Socket> connect() async {
        for (final address in addresses.take(2)) {
          if (cancelled) throw const SocketException('Maps lookup cancelled');
          try {
            tcp = await Socket.startConnect(address, 443);
            if (cancelled) {
              tcp!.cancel();
              throw const SocketException('Maps lookup cancelled');
            }
            raw = await tcp!.socket.timeout(const Duration(seconds: 2));
            if (cancelled) {
              raw!.destroy();
              throw const SocketException('Maps lookup cancelled');
            }
            // Keep the ORIGINAL hostname for SNI and certificate verification.
            // Never install a badCertificateCallback or use an IP as the URL.
            secure = await SecureSocket.secure(
              raw!,
              host: uri.host,
            ).timeout(const Duration(seconds: 3));
            if (cancelled) {
              secure!.destroy();
              throw const SocketException('Maps lookup cancelled');
            }
            return secure!;
          } on HandshakeException {
            raw?.destroy();
            rethrow;
          } on SocketException {
            tcp?.cancel();
            raw?.destroy();
          } on TimeoutException {
            tcp?.cancel();
            raw?.destroy();
          }
        }
        throw const SocketException('Could not connect to Google Maps');
      }

      return ConnectionTask.fromSocket(connect(), cancel);
    };
    return client;
  }

  Future<List<InternetAddress>> _addresses(
    String host,
    void Function(HttpClient) ownClient,
  ) async {
    final client = _dnsClientFactory();
    ownClient(client);
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(
        Uri.https('dns.google', '/resolve', {
          'name': host,
          'type': 'A',
          'edns_client_subnet': '0.0.0.0/0',
        }),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw const SocketException('Maps DNS lookup failed');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 16384) {
          throw const FormatException('Oversized DNS response');
        }
      }
      return parseAddresses(jsonDecode(utf8.decode(bytes)), host);
    } finally {
      client.close(force: true);
    }
  }

  static List<InternetAddress> parseAddresses(Object? value, String host) {
    if (!hosts.contains(host) ||
        value is! Map ||
        value['Status'] != 0 ||
        value['Answer'] is! List) {
      throw const FormatException('Invalid Maps DNS response');
    }
    final question = value['Question'];
    if (question is! List ||
        question.length != 1 ||
        question.first is! Map ||
        question.first['name'].toString().replaceFirst(RegExp(r'\.$'), '') !=
            host ||
        question.first['type'] != 1) {
      throw const FormatException('Unexpected Maps DNS question');
    }
    final addresses = <InternetAddress>[];
    for (final record in value['Answer'] as List) {
      if (record is! Map || record['type'] != 1 || record['data'] is! String) {
        continue;
      }
      final address = InternetAddress.tryParse(record['data']);
      if (address == null ||
          address.type != InternetAddressType.IPv4 ||
          address.isLoopback ||
          address.isLinkLocal) {
        continue;
      }
      final b = address.rawAddress;
      if (b[0] == 0 ||
          b[0] == 10 ||
          b[0] >= 224 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168)) {
        continue;
      }
      addresses.add(address);
    }
    if (addresses.isEmpty) {
      throw const FormatException('No usable Maps DNS answer');
    }
    return addresses;
  }
}

import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';

/// Discovers other CopyPasta peers on the same Wi-Fi network.
/// This class uses mDNS to find devices advertising the _copypasta._tcp.local service.
class MdnsService {
  /// Discover peers that advertise _copypasta._tcp.local
  Future<List<String>> discoverPeers({int timeoutSec = 3}) async {
    final client = MDnsClient();
    final peers = <String>[];

    try {
      await client.start();
      print('Searching for CopyPasta peers via mDNS...');

      // Query for the _copypasta._tcp service
      await for (final PtrResourceRecord ptr
          in client.lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('_copypasta._tcp.local'))) {
        await for (final SrvResourceRecord srv
            in client.lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(ptr.domainName))) {
          // Get the IP addresses associated with this service
          await for (final IPAddressResourceRecord ip
              in client.lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target))) {
            peers.add(ip.address.address);
          }
        }
      }

      // Wait a moment before closing
      await Future.delayed(Duration(seconds: timeoutSec));
    } catch (e) {
      print('mDNS discovery error: $e');
    } finally {
      client.stop(); // This returns void, so no await
    }

    return peers.toSet().toList();
  }
}

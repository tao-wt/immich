import 'package:dlna_dart/dlna_dart.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final dlnaRepositoryProvider = Provider((_) {
  return DLNARepository();
});

class DLNARepository {
  DlnaDevice? _currentDevice;
  final DLNADiscovery _discovery = DLNADiscovery();

  void Function(DlnaEvent? event)? onDlnaEvent;

  DLNARepository();

  Future<List<DlnaDevice>> listDestinations() async {
    _discovery.start();
    await Future.delayed(const Duration(seconds: 3));
    _discovery.stop();
    return _discovery.deviceList;
  }

  Future<void> connect(DlnaDevice device) async {
    _currentDevice = device;
    _currentDevice?.eventStream.listen((event) {
      onDlnaEvent?.call(event);
    });
  }

  Future<void> disconnect() async {
    if (_currentDevice != null) {
      await stop();
      _currentDevice = null;
    }
    _discovery.stop();
  }

  Future<void> setUri(String uri, String title, String? mimeType) async {
    if (_currentDevice == null) {
      throw Exception("DLNA device is not connected");
    }

    final metadata = _buildMetadata(uri, title, mimeType);
    await _currentDevice!.avTransport.service.setAVTransportURI(
      instanceID: 0,
      currentURI: uri,
      currentURIMetaData: metadata,
    );
  }

  Future<void> play() async {
    if (_currentDevice == null) {
      throw Exception("DLNA device is not connected");
    }
    await _currentDevice!.avTransport.service.play(
      instanceID: 0,
      speed: "1",
    );
  }

  Future<void> pause() async {
    if (_currentDevice == null) {
      throw Exception("DLNA device is not connected");
    }
    await _currentDevice!.avTransport.service.pause(
      instanceID: 0,
    );
  }

  Future<void> seekTo(Duration position) async {
    if (_currentDevice == null) {
      throw Exception("DLNA device is not connected");
    }
    final time = _formatDuration(position);
    await _currentDevice!.avTransport.service.seek(
      instanceID: 0,
      unit: "REL_TIME",
      target: time,
    );
  }

  Future<void> stop() async {
    if (_currentDevice == null) {
      throw Exception("DLNA device is not connected");
    }
    await _currentDevice!.avTransport.service.stop(
      instanceID: 0,
    );
  }

  Future<DlnaPositionInfo?> getPositionInfo() async {
    if (_currentDevice == null) {
      return null;
    }
    return await _currentDevice!.avTransport.service.getPositionInfo(
      instanceID: 0,
    );
  }

  Future<DlnaTransportInfo?> getTransportInfo() async {
    if (_currentDevice == null) {
      return null;
    }
    return await _currentDevice!.avTransport.service.getTransportInfo(
      instanceID: 0,
    );
  }

  DlnaDevice? get currentDevice => _currentDevice;

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _buildMetadata(String uri, String title, String? mimeType) {
    final protocolInfo = 'http-get:*:${mimeType ?? '*/*'}:*';
    return '''<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <item id="1" parentID="0" restricted="1">
            <dc:title>$title</dc:title>
            <upnp:class>object.item.videoItem</upnp:class>
            <res protocolInfo="$protocolInfo">$uri</res>
        </item>
    </DIDL-Lite>''';
  }
}

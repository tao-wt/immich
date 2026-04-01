import 'dart:async';

import 'package:dlna_dart/dlna_dart.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/models/cast/cast_manager_state.dart';
import 'package:immich_mobile/models/sessions/session_create_response.model.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/dlna.repository';
import 'package:immich_mobile/repositories/sessions_api.repository.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
// ignore: import_rule_openapi, we are only using the AssetMediaSize enum
import 'package:openapi/api.dart';

final dlnaServiceProvider = Provider(
  (ref) => DLNAService(
    ref.watch(dlnaRepositoryProvider),
    ref.watch(sessionsAPIRepositoryProvider),
    ref.watch(assetApiRepositoryProvider),
  ),
);

class DLNAService {
  final DLNARepository _dlnaRepository;
  final SessionsAPIRepository _sessionsApiService;
  final AssetApiRepository _assetApiRepository;

  SessionCreateResponse? sessionKey;
  String? currentAssetId;
  bool isConnected = false;
  Timer? _mediaStatusPollingTimer;

  void Function(bool)? onConnectionState;
  void Function(Duration)? onCurrentTime;
  void Function(Duration)? onDuration;
  void Function(String)? onReceiverName;
  void Function(CastState)? onCastState;

  DLNAService(this._dlnaRepository, this._sessionsApiService, this._assetApiRepository) {
    _dlnaRepository.onDlnaEvent = _onDlnaEventCallback;
  }

  void _onDlnaEventCallback(DlnaEvent? event) {
    // Handle DLNA events
    if (event != null) {
      _updatePlaybackState();
    }
  }

  void _updatePlaybackState() async {
    if (!isConnected) return;

    final transportInfo = await _dlnaRepository.getTransportInfo();
    final positionInfo = await _dlnaRepository.getPositionInfo();

    if (transportInfo == null) return;

    // Update cast state based on transport state
    switch (transportInfo.currentTransportState) {
      case "PLAYING":
        onCastState?.call(CastState.playing);
        break;
      case "PAUSED_PLAYBACK":
        onCastState?.call(CastState.paused);
        break;
      case "STOPPED":
        onCastState?.call(CastState.idle);
        _mediaStatusPollingTimer?.cancel();
        currentAssetId = null;
        break;
      case "TRANSITIONING":
        onCastState?.call(CastState.buffering);
        break;
      default:
        onCastState?.call(CastState.idle);
    }

    if (positionInfo != null) {
      final currentTime = _parseTime(positionInfo.relTime);
      final duration = _parseTime(positionInfo.trackDuration);
      onCurrentTime?.call(currentTime);
      onDuration?.call(duration);
    }
  }

  Duration _parseTime(String? timeStr) {
    if (timeStr == null || timeStr == "NOT_IMPLEMENTED" || timeStr.isEmpty) {
      return Duration.zero;
    }
    final parts = timeStr.split(':');
    if (parts.length != 3) {
      return Duration.zero;
    }
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = int.tryParse(parts[2]) ?? 0;
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  Future<void> connect(dynamic device) async {
    await _dlnaRepository.connect(device);
    isConnected = true;
    onConnectionState?.call(true);
    onReceiverName?.call(device.friendlyName ?? "DLNA Device");
  }

  CastDestinationType getType() {
    return CastDestinationType.dlna;
  }

  Future<bool> initialize() async {
    // DLNA doesn't require special initialization
    return true;
  }

  Future<void> disconnect() async {
    onReceiverName?.call("");
    currentAssetId = null;
    isConnected = false;
    onConnectionState?.call(false);
    await _dlnaRepository.disconnect();
    _mediaStatusPollingTimer?.cancel();
  }

  bool isSessionValid() {
    if (sessionKey == null || sessionKey?.expiresAt == null) {
      return false;
    }

    final tokenExpiration = DateTime.parse(sessionKey!.expiresAt!);
    final bufferedExpiration = tokenExpiration.subtract(const Duration(seconds: 10));
    return bufferedExpiration.isAfter(DateTime.now());
  }

  void loadMedia(RemoteAsset asset, bool reload) async {
    if (!isConnected) {
      return;
    } else if (asset.id == currentAssetId && !reload) {
      return;
    }

    if (!isSessionValid()) {
      sessionKey = await _sessionsApiService.createSession(
        "Cast",
        "DLNA",
        duration: const Duration(minutes: 15).inSeconds,
      );
    }

    final unauthenticatedUrl = asset.isVideo
        ? getPlaybackUrlForRemoteId(asset.id)
        : getThumbnailUrlForRemoteId(asset.id, type: AssetMediaSize.fullsize);

    final authenticatedURL = "$unauthenticatedUrl&sessionKey=${sessionKey?.token}";
    final mimeType = await _assetApiRepository.getAssetMIMEType(asset.id);

    if (mimeType == null) {
      return;
    }

    await _dlnaRepository.setUri(
      authenticatedURL,
      asset.fileName ?? "Immich Media",
      mimeType,
    );

    await _dlnaRepository.play();
    currentAssetId = asset.id;

    _mediaStatusPollingTimer?.cancel();

    if (asset.isVideo) {
      _mediaStatusPollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (isConnected) {
          _updatePlaybackState();
        } else {
          timer.cancel();
        }
      });
    }
  }

  void play() {
    _dlnaRepository.play();
  }

  void pause() {
    _dlnaRepository.pause();
  }

  void seekTo(Duration position) {
    _dlnaRepository.seekTo(position);
  }

  void stop() {
    _dlnaRepository.stop();
    _mediaStatusPollingTimer?.cancel();
    currentAssetId = null;
  }

  bool _isMediaRenderer(DlnaDevice device) {
    // Check if device has MediaRenderer service
    return device.services.any((service) =>
        service.serviceType.contains('MediaRenderer') ||
        service.serviceId.contains('MediaRenderer'));
  }

  Future<List<(String, CastDestinationType, dynamic)>> getDevices() async {
    final devices = await _dlnaRepository.listDestinations();

    return devices
        .where(_isMediaRenderer)
        .map((device) => (device.friendlyName ?? "DLNA Device", CastDestinationType.dlna, device))
        .toList(growable: false);
  }
}

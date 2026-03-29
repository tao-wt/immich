import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';

class GiteeIpv6Service {
  final _log = Logger("GiteeIpv6Service");
  final ApiService _apiService;

  GiteeIpv6Service(this._apiService);

  /// 检查是否启用了 Gitee IPv6 自动更新
  bool isEnabled() {
    return Store.get(StoreKey.enableGiteeIpv6Update, false);
  }

  /// 获取配置的 Gitee 访问令牌
  String? getAccessToken() {
    return Store.tryGet(StoreKey.giteeAccessToken);
  }

  /// 获取用户名
  String? getUsername() {
    return Store.tryGet(StoreKey.giteeUsername);
  }

  /// 获取仓库名称
  String? getRepoName() {
    return Store.tryGet(StoreKey.giteeRepoName);
  }

  /// 获取文件路径
  String? getFilePath() {
    return Store.tryGet(StoreKey.giteeFilePath);
  }

  /// 获取指定的网卡名称
  String? getInterfaceName() {
    return Store.tryGet(StoreKey.giteeInterfaceName);
  }

  /// 检查配置是否完整
  bool isConfigComplete() {
    final token = getAccessToken();
    final username = getUsername();
    final repo = getRepoName();
    final path = getFilePath();
    return token != null && token.isNotEmpty &&
           username != null && username.isNotEmpty &&
           repo != null && repo.isNotEmpty &&
           path != null && path.isNotEmpty;
  }

  /// 从 Gitee API 获取文件内容
  Future<String?> fetchFileContent() async {
    if (!isEnabled()) {
      _log.info("Gitee IPv6 auto-update is disabled");
      return null;
    }

    if (!isConfigComplete()) {
      _log.warning("Gitee configuration is incomplete");
      return null;
    }

    final token = getAccessToken()!;
    final username = getUsername()!;
    final repo = getRepoName()!;
    final path = getFilePath()!;

    // Gitee API URL: https://gitee.com/api/v5/repos/{owner}/{repo}/contents/{path}
    final uri = Uri.parse("https://gitee.com/api/v5/repos/$username/$repo/contents/$path");

    try {
      _log.info("Fetching file from Gitee: $uri");
      final response = await NetworkRepository.client.get(
        uri.replace(queryParameters: {'access_token': token}),
      ).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Gitee API returns content encoded in base64
        final String base64Content = data['content'] as String;
        final String content = utf8.decode(base64.decode(base64Content));
        _log.info("Successfully fetched file from Gitee, size: ${content.length} bytes");
        return content;
      } else {
        _log.severe("Failed to fetch from Gitee, status code: ${response.statusCode}, response: ${response.body}");
        return null;
      }
    } catch (e, stack) {
      _log.severe("Error fetching file from Gitee", e, stack);
      return null;
    }
  }

  /// 从 ip a s 输出解析 IPv6 地址
  /// 返回第一个符合条件的公网 IPv6 地址
  String? extractIpv6FromContent(String content) {
    final interfaceName = getInterfaceName();
    final List<String> lines = content.split('\n');

    String? currentInterface;
    List<String> candidateIps = [];

    for (final line in lines) {
      final trimmedLine = line.trim();

      // 检测网卡行：类似 "2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> ..."
      if (trimmedLine.contains(RegExp(r'^\d+:\s+[\w\d]+:.*$'))) {
        final match = RegExp(r'^\d+:\s+([\w\d]+):').firstMatch(trimmedLine);
        if (match != null) {
          currentInterface = match.group(1);
          _log.fine("Found interface: $currentInterface");
        }
        continue;
      }

      // 如果指定了网卡名称，跳过其他网卡
      if (interfaceName != null && interfaceName.isNotEmpty) {
        if (currentInterface != interfaceName) {
          continue;
        }
      }

      // 检测 inet6 行：类似 "inet6 2409:xxxx:xxxx:xxxx::1/64 scope global ..."
      if (trimmedLine.startsWith('inet6')) {
        final match = RegExp(r'inet6\s+([0-9a-fA-F:]+)/\d+').firstMatch(trimmedLine);
        if (match != null) {
          final ipv6 = match.group(1);
          if (ipv6 != null && _isPublicIpv6(ipv6)) {
            candidateIps.add(ipv6);
            _log.info("Found candidate public IPv6: $ipv6 on interface $currentInterface");
          }
        }
      }
    }

    if (candidateIps.isEmpty) {
      _log.warning("No valid public IPv6 address found in content");
      return null;
    }

    // 返回第一个符合条件的 IPv6
    _log.info("Selected first candidate IPv6: ${candidateIps.first}");
    return candidateIps.first;
  }

  /// 检查是否是公网 IPv6 地址
  /// 排除：
  /// - 链路本地地址：fe80::/10 (fe80: - febf:)
  /// - 唯一本地地址（内网）：fc00::/7 (fc00: - fdff:)
  /// - 环回地址：::1/128
  bool _isPublicIpv6(String ipv6) {
    // 转换为小写处理
    final lower = ipv6.toLowerCase();

    // 链路本地地址 fe80::/10
    if (lower.startsWith('fe8') || lower.startsWith('fe9') || lower.startsWith('fea') || lower.startsWith('feb')) {
      return false;
    }

    // 唯一本地地址 fc00::/7
    if (lower.startsWith('fc') || lower.startsWith('fd')) {
      return false;
    }

    // 环回地址 ::1
    if (lower == '::1') {
      return false;
    }

    // 未指定地址 ::
    if (lower == '::') {
      return false;
    }

    return true;
  }

  /// 更新服务器地址
  /// 如果获取成功，则更新外部网络列表中的第一个地址
  Future<String?> updateServerAddress() async {
    // 获取文件内容
    final content = await fetchFileContent();
    if (content == null) {
      return null;
    }

    // 解析 IPv6
    final newIpv6 = extractIpv6FromContent(content);
    if (newIpv6 == null) {
      _log.warning("Failed to extract valid IPv6 from file content");
      return null;
    }

    // 获取当前保存的外部端点列表
    final externalJson = Store.tryGet(StoreKey.externalEndpointList);
    if (externalJson == null) {
      _log.warning("No external endpoint list found in storage");
      return null;
    }

    try {
      // 解析现有列表
      List<dynamic> list = jsonDecode(externalJson);

      // 直接构建固定格式 URL: http://[ipv6]:2283
      final newExternalUrl = "http://[$newIpv6]:2283";
      _log.info("New external IPv6 URL: $newExternalUrl");

      if (list.isEmpty) {
        // 列表为空，添加第一个
        _log.info("External list is empty, adding new endpoint");
        final newEndpoint = AuxilaryEndpoint(
          url: newExternalUrl,
          status: const AuxCheckStatus.unknown(),
        );
        list.add(jsonDecode(newEndpoint.toJson()));
      } else {
        // 覆盖第一个端点
        final first = AuxilaryEndpoint.fromJson(list[0] as String);
        if (newExternalUrl == first.url) {
          _log.info("External IPv6 address unchanged, skipping update");
          return newExternalUrl;
        }
        _log.info("External IPv6 address changed, replacing first entry");
        final newFirst = first.copyWith(url: newExternalUrl, status: const AuxCheckStatus.unknown());
        list[0] = jsonDecode(newFirst.toJson());
      }

      // 保存回存储
      await Store.put(StoreKey.externalEndpointList, jsonEncode(list));

      _log.info("External IPv6 address updated successfully to: $newExternalUrl");
      return newExternalUrl;
    } catch (e, stack) {
      _log.severe("Failed to update external IPv6 address", e, stack);
      return null;
    }
  }
}

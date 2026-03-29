import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/network.provider.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/settings/networking_settings/external_network_preference.dart';
import 'package:immich_mobile/widgets/settings/networking_settings/local_network_preference.dart';
import 'package:immich_mobile/widgets/settings/setting_group_title.dart';
import 'package:immich_mobile/widgets/settings/settings_switch_list_tile.dart';
import 'package:logging/logging.dart';

class NetworkingSettings extends HookConsumerWidget {
  const NetworkingSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentEndpoint = getServerUrl();
    final featureEnabled = useAppSettingsState(AppSettingsEnum.autoEndpointSwitching);

    Future<void> checkWifiReadPermission() async {
      final [hasLocationInUse, hasLocationAlways] = await Future.wait([
        ref.read(networkProvider.notifier).getWifiReadPermission(),
        ref.read(networkProvider.notifier).getWifiReadBackgroundPermission(),
      ]);

      bool? isGrantLocationAlwaysPermission;

      if (!hasLocationInUse) {
        await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text("location_permission".tr()),
              content: Text("location_permission_content".tr()),
              actions: [
                TextButton(
                  onPressed: () async {
                    final isGrant = await ref.read(networkProvider.notifier).requestWifiReadPermission();

                    Navigator.pop(context, isGrant);
                  },
                  child: Text("grant_permission".tr()),
                ),
              ],
            );
          },
        );
      }

      if (!hasLocationAlways) {
        isGrantLocationAlwaysPermission = await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text("background_location_permission".tr()),
              content: Text("background_location_permission_content".tr()),
              actions: [
                TextButton(
                  onPressed: () async {
                    final isGrant = await ref.read(networkProvider.notifier).requestWifiReadBackgroundPermission();

                    Navigator.pop(context, isGrant);
                  },
                  child: Text("grant_permission".tr()),
                ),
              ],
            );
          },
        );
      }

      if (isGrantLocationAlwaysPermission != null && !isGrantLocationAlwaysPermission) {
        await ref.read(networkProvider.notifier).openSettings();
      }
    }

    useEffect(() {
      if (featureEnabled.value == true) {
        checkWifiReadPermission();
      }
      return null;
    }, [featureEnabled.value]);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        const SizedBox(height: 8),
        SettingGroupTitle(
          title: "current_server_address".t(context: context),
          icon: (currentEndpoint?.startsWith('https') ?? false) ? Icons.https_outlined : Icons.http_outlined,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: BorderSide(color: context.colorScheme.surfaceContainerHighest, width: 1),
            ),
            child: ListTile(
              leading: currentEndpoint != null
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : const Icon(Icons.circle_outlined),
              title: Text(
                currentEndpoint ?? "--",
                style: TextStyle(fontSize: 14, fontFamily: 'GoogleSansCode', color: context.primaryColor),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Divider(color: context.colorScheme.surfaceContainerHighest),
        ),
        SettingsSwitchListTile(
          enabled: true,
          valueNotifier: featureEnabled,
          title: "automatic_endpoint_switching_title".tr(),
          subtitle: "automatic_endpoint_switching_subtitle".tr(),
        ),
        const SizedBox(height: 8),
        SettingGroupTitle(
          title: "local_network".t(context: context),
          icon: Icons.home_outlined,
        ),
        LocalNetworkPreference(enabled: featureEnabled.value),
        const SizedBox(height: 16),
        SettingGroupTitle(
          title: "external_network".t(context: context),
          icon: Icons.dns_outlined,
        ),
        ExternalNetworkPreference(enabled: featureEnabled.value),
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Divider(color: context.colorScheme.surfaceContainerHighest),
        ),
        SettingGroupTitle(
          title: "gitee_ipv6_title".tr(),
          icon: Icons.update_outlined,
        ),
        _GiteeIpv6Settings(),
      ],
    );
  }
}

class NetworkStatusIcon extends StatelessWidget {
  const NetworkStatusIcon({super.key, required this.status, this.enabled = true}) : super();

  final AuxCheckStatus status;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: buildIcon(context));
  }

  Widget buildIcon(BuildContext context) => switch (status) {
    AuxCheckStatus.loading => Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(color: context.primaryColor, strokeWidth: 2, key: const ValueKey('loading')),
      ),
    ),
    AuxCheckStatus.valid =>
      enabled
          ? const Icon(Icons.check_circle_rounded, color: Colors.green, key: ValueKey('success'))
          : Icon(
              Icons.check_circle_rounded,
              color: context.colorScheme.onSurface.withAlpha(100),
              key: const ValueKey('success'),
            ),
    AuxCheckStatus.error =>
      enabled
          ? const Icon(Icons.error_rounded, color: Colors.red, key: ValueKey('error'))
          : const Icon(Icons.error_rounded, color: Colors.grey, key: ValueKey('error')),
    _ => const Icon(Icons.circle_outlined, key: ValueKey('unknown')),
  };
}

class _GiteeIpv6Settings extends HookConsumerWidget {
  final _log = Logger("GiteeIpv6Settings");

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = Store.get(StoreKey.enableGiteeIpv6Update, false);
    final token = Store.tryGet(StoreKey.giteeAccessToken) ?? '';
    final username = Store.tryGet(StoreKey.giteeUsername) ?? '';
    final repo = Store.tryGet(StoreKey.giteeRepoName) ?? '';
    final path = Store.tryGet(StoreKey.giteeFilePath) ?? '';
    final interface = Store.tryGet(StoreKey.giteeInterfaceName) ?? '';

    final enabledState = useState(enabled);
    final tokenController = useTextEditingController(text: token);
    final usernameController = useTextEditingController(text: username);
    final repoController = useTextEditingController(text: repo);
    final pathController = useTextEditingController(text: path);
    final interfaceController = useTextEditingController(text: interface);
    final isLoading = useState(false);
    final lastResult = useState<String?>(null);

    Future<void> manualUpdate() async {
      isLoading.value = true;
      lastResult.value = null;

      try {
        final result = await ref.read(giteeIpv6ServiceProvider).updateServerAddress();
        if (result != null) {
          lastResult.value = "gitee_update_success".tr(args: [result]);
        } else {
          lastResult.value = "gitee_update_failed".tr();
        }
      } catch (e, stack) {
        _log.severe("Error manual updating from Gitee", e, stack);
        lastResult.value = "gitee_update_error".tr(args: [e.toString()]);
      } finally {
        isLoading.value = false;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          SettingsSwitchListTile(
            enabled: true,
            valueNotifier: enabledState,
            title: "enable_gitee_ipv6_update_title".tr(),
            subtitle: "enable_gitee_ipv6_update_subtitle".tr(),
            onChanged: (value) async {
              await Store.put(StoreKey.enableGiteeIpv6Update, value);
              enabledState.value = value;
            },
          ),
          if (enabledState.value)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  side: BorderSide(color: context.colorScheme.surfaceContainerHighest, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "gitee_access_token".tr(),
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: tokenController,
                        decoration: InputDecoration(
                          hintText: "gitee_access_token_hint".tr(),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        obscureText: true,
                        onChanged: (value) async {
                          await Store.put(StoreKey.giteeAccessToken, value.trim());
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "gitee_username".tr(),
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: usernameController,
                        decoration: InputDecoration(
                          hintText: "gitee_username_hint".tr(),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onChanged: (value) async {
                          await Store.put(StoreKey.giteeUsername, value.trim());
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "gitee_repo_name".tr(),
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: repoController,
                        decoration: InputDecoration(
                          hintText: "gitee_repo_name_hint".tr(),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onChanged: (value) async {
                          await Store.put(StoreKey.giteeRepoName, value.trim());
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "gitee_file_path".tr(),
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: pathController,
                        decoration: InputDecoration(
                          hintText: "gitee_file_path_hint".tr(),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onChanged: (value) async {
                          await Store.put(StoreKey.giteeFilePath, value.trim());
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "gitee_interface_name".tr(),
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: interfaceController,
                        decoration: InputDecoration(
                          hintText: "gitee_interface_name_hint".tr(),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onChanged: (value) async {
                          await Store.put(StoreKey.giteeInterfaceName, value.trim());
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading.value ? null : manualUpdate,
                          child: isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text("gitee_manual_update".tr()),
                        ),
                      ),
                      if (lastResult.value != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: lastResult.value!.startsWith('✅')
                                ? Colors.green.withAlpha(50)
                                : Colors.red.withAlpha(50),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lastResult.value!,
                            style: context.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

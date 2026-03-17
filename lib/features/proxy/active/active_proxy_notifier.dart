import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/utils/throttler.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart';
import 'package:hiddify/features/proxy/model/proxy_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_proxy_notifier.g.dart';

@riverpod
class ActiveProxyNotifier extends _$ActiveProxyNotifier {
  @override
  Stream<ProxyEntity?> build() async* {
    final stream = ref.watch(proxyRepositoryProvider).watchActiveProxy();
    await for (final proxy in stream) {
      // ---> ПЕРЕХВАТЧИК BALANCE <---
      if (proxy != null && proxy.tag == "balance") {
        ref.read(proxyRepositoryProvider).selectProxy("PROXY", "auto").run();
      }
      yield proxy;
    }
  }
}

@riverpod
class IpInfoNotifier extends _$IpInfoNotifier with AppLogger {
  @override
  Stream<IpInfo> build() async* {
    final connected = await ref.watch(
      connectionNotifierProvider.selectAsync((data) => data.isConnected),
    );
    if (!connected) return;

    final proxyEither = await ref.watch(activeProxyNotifierProvider.future);
    if (proxyEither == null) return;

    yield* _ipInfoStream(proxyEither.tag).distinct();
  }

  bool _idle = false;
  Timer? timer;

  Stream<IpInfo> _ipInfoStream(String tag) async* {
    final throttle = Throttler(const Duration(milliseconds: 100));
    final dio = ref.watch(dioProvider);

    while (true) {
      if (_idle) {
        loggy.debug("idle");
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      loggy.debug("fetching ip info");

      try {
        if (!ref.read(Preferences.connectionIpCheck)) {
          loggy.debug("ip check is disabled");
          yield const IpInfo.disabled();
          _idle = true;
          continue;
        }
        final response = await dio.get<Map<String, dynamic>>(
          "http://cp.cloudflare.com",
          options: Options(
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
          ),
        );
        yield IpInfo.fromJson(response.data!);
      } on DioException catch (e) {
        loggy.warning("error getting ip info");
        loggy.debug(e.message);
        yield IpInfo.error(e.message ?? "network error");
      } catch (e) {
        loggy.warning("error getting ip info", e);
        yield const IpInfo.error("unknown error");
      }

      timer = Timer(const Duration(seconds: 10), () {
        _idle = true;
        loggy.debug("idling ip check");
      });
      throttle.call(() => _idle = false);
    }
  }
}

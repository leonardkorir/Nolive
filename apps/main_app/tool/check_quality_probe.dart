import 'dart:io';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

Future<void> main(List<String> args) async {
  final providerId = ProviderId(args.isNotEmpty ? args[0] : 'bilibili');
  final roomId = args.length > 1 ? args[1] : '6';
  final registry = ReferenceProviderCatalog.buildLiveRegistry(
    stringSetting: (_) => '',
    intSetting: (_) => 0,
  );
  final provider = registry.create(providerId);
  final detail = await provider
      .requireContract<SupportsRoomDetail>(ProviderCapability.roomDetail)
      .fetchRoomDetail(roomId);
  final qualities = await provider
      .requireContract<SupportsPlayQualities>(ProviderCapability.playQualities)
      .fetchPlayQualities(detail);
  stdout.writeln(
      'detail: ${detail.title} / ${detail.roomId} / ${detail.streamerName}');
  for (final q in qualities) {
    final urls = await provider
        .requireContract<SupportsPlayUrls>(ProviderCapability.playUrls)
        .fetchPlayUrls(detail: detail, quality: q);
    stdout.writeln(
        'QUALITY ${q.id} ${q.label} default=${q.isDefault} sort=${q.sortOrder} count=${urls.length}');
    for (final u in urls.take(3)) {
      stdout.writeln('  ${u.lineLabel} -> ${u.url}');
    }
  }
}

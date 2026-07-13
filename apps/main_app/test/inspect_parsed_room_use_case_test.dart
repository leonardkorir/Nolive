import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/parse/application/inspect_parsed_room_use_case.dart';
import 'package:nolive_app/src/features/parse/application/parse_room_input_use_case.dart';

void main() {
  test(
    'inspect parsed room allows chaturbate without browser cookie',
    () async {
      var created = 0;
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: ChaturbateProvider.kDescriptor,
            builder: () {
              created += 1;
              return _FakeChaturbateRoomDetailProvider();
            },
          ),
        );
      final useCase = InspectParsedRoomUseCase(registry);

      final inspection = await useCase(
        const ParsedRoomInput(
          providerId: ProviderId.chaturbate,
          providerName: 'Chaturbate',
          roomId: 'kittengirlxo',
          normalizedInput: 'https://chaturbate.com/kittengirlxo/',
        ),
      );

      expect(inspection.detail.roomId, 'kittengirlxo');
      expect(inspection.detail.streamerName, 'kittengirlxo');
      expect(created, 1);
    },
  );

  test('inspect parsed room prefers injected room detail override', () async {
    var fetchRoomDetailCalls = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: ChaturbateProvider.kDescriptor,
          builder: () => _FakeChaturbateRoomDetailProvider(
            onFetchRoomDetail: () {
              fetchRoomDetailCalls += 1;
            },
          ),
        ),
      );
    final useCase = InspectParsedRoomUseCase(
      registry,
      roomDetailOverride: ({required providerId, required roomId}) async {
        if (providerId != ProviderId.chaturbate) {
          return null;
        }
        return LiveRoomDetail(
          providerId: providerId,
          roomId: roomId,
          title: 'override room',
          streamerName: roomId,
          isLive: true,
          sourceUrl: 'https://chaturbate.com/$roomId/',
        );
      },
    );

    final inspection = await useCase(
      const ParsedRoomInput(
        providerId: ProviderId.chaturbate,
        providerName: 'Chaturbate',
        roomId: 'milabunny_',
        normalizedInput: 'https://chaturbate.com/milabunny_/',
      ),
    );

    expect(inspection.detail.title, 'override room');
    expect(fetchRoomDetailCalls, 0);
  });
}

class _FakeChaturbateRoomDetailProvider extends LiveProvider
    implements SupportsRoomDetail {
  _FakeChaturbateRoomDetailProvider({this.onFetchRoomDetail});

  final void Function()? onFetchRoomDetail;

  @override
  ProviderDescriptor get descriptor => ChaturbateProvider.kDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    onFetchRoomDetail?.call();
    return LiveRoomDetail(
      providerId: ProviderId.chaturbate,
      roomId: roomId,
      title: '$roomId room',
      streamerName: roomId,
      isLive: true,
      coverUrl: null,
      keyframeUrl: null,
      sourceUrl: 'https://chaturbate.com/$roomId/',
      danmakuToken: null,
      metadata: const <String, Object?>{},
    );
  }
}

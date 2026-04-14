import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/parse/application/inspect_parsed_room_use_case.dart';
import 'package:nolive_app/src/features/parse/application/parse_room_input_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test('inspect parsed room fails fast for chaturbate without browser cookie',
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
    final settingsRepository = InMemorySettingsRepository();
    final secureCredentialStore = InMemorySecureCredentialStore();
    final useCase = InspectParsedRoomUseCase(
      registry,
      loadProviderAccountSettings: LoadProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      ),
      requireChaturbateCookiePreflight: true,
    );

    await expectLater(
      () => useCase(
        const ParsedRoomInput(
          providerId: ProviderId.chaturbate,
          providerName: 'Chaturbate',
          roomId: 'kittengirlxo',
          normalizedInput: 'https://chaturbate.com/kittengirlxo/',
        ),
      ),
      throwsA(
        isA<ProviderParseException>().having(
          (error) => error.message,
          'message',
          allOf(contains('浏览器 Cookie'), contains('账号管理')),
        ),
      ),
    );
    expect(created, 0);
  });

  test('inspect parsed room allows chaturbate after cookie preflight',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: ChaturbateProvider.kDescriptor,
          builder: _FakeChaturbateRoomDetailProvider.new,
        ),
      );
    final settingsRepository = InMemorySettingsRepository();
    final secureCredentialStore = InMemorySecureCredentialStore(
      initialValues: const {
        'account_chaturbate_cookie': 'csrftoken=demo; __cf_bm=demo-bm',
      },
    );
    final useCase = InspectParsedRoomUseCase(
      registry,
      loadProviderAccountSettings: LoadProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      ),
      requireChaturbateCookiePreflight: true,
    );

    final inspection = await useCase(
      const ParsedRoomInput(
        providerId: ProviderId.chaturbate,
        providerName: 'Chaturbate',
        roomId: 'kittengirlxo',
        normalizedInput: 'chaturbate:kittengirlxo',
      ),
    );

    expect(inspection.detail.roomId, 'kittengirlxo');
    expect(inspection.detail.streamerName, 'kittengirlxo');
  });

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
    final settingsRepository = InMemorySettingsRepository();
    final secureCredentialStore = InMemorySecureCredentialStore(
      initialValues: const {
        'account_chaturbate_cookie': 'cf_clearance=demo; csrftoken=demo',
      },
    );
    final useCase = InspectParsedRoomUseCase(
      registry,
      loadProviderAccountSettings: LoadProviderAccountSettingsUseCase(
        settingsRepository,
        secureCredentialStore,
      ),
      requireChaturbateCookiePreflight: true,
      roomDetailOverride: ({
        required providerId,
        required roomId,
      }) async {
        if (providerId != ProviderId.chaturbate) {
          return null;
        }
        return LiveRoomDetail(
          providerId: providerId.value,
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
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: '$roomId room',
      streamerName: roomId,
      isLive: true,
      coverUrl: null,
      keyframeUrl: null,
      sourceUrl: 'https://chaturbate.com/$roomId/',
      danmakuToken: const <String, dynamic>{},
      metadata: const <String, Object?>{},
    );
  }
}

import 'package:live_providers/src/providers/twitch/twitch_api_client.dart';
import 'package:live_providers/src/providers/twitch/twitch_live_data_source.dart';
import 'package:test/test.dart';

void main() {
  test('twitch live data source maps native categories from directory payload',
      () async {
    final dataSource = TwitchLiveDataSource(
      apiClient: _FakeTwitchCategoryApiClient(),
    );

    final categories = await dataSource.fetchCategories();
    expect(categories, hasLength(1));
    expect(categories.single.children.length, greaterThanOrEqualTo(2));

    final justChatting = categories.single.children.firstWhere(
      (item) => item.name == 'Just Chatting',
    );
    expect(justChatting.id, 'just-chatting');
    expect(justChatting.pic, contains('144x192'));

    final firstPage = await dataSource.fetchCategoryRooms(
      justChatting,
      page: 1,
    );
    expect(firstPage.items, hasLength(30));
    expect(firstPage.hasMore, isTrue);
    expect(
      firstPage.items.map((item) => item.roomId),
      containsAll(['xqc', 'arky']),
    );
    expect(
      firstPage.items.every((item) => item.areaName == 'Just Chatting'),
      isTrue,
    );

    final secondPage = await dataSource.fetchCategoryRooms(
      justChatting,
      page: 2,
    );
    expect(secondPage.items, hasLength(10));
    expect(secondPage.hasMore, isFalse);
  });

  test('twitch live data source expands recommend feed with category windows',
      () async {
    final dataSource = TwitchLiveDataSource(
      apiClient: _FakeTwitchCategoryApiClient(),
    );

    final firstPage = await dataSource.fetchRecommendRooms(page: 1);
    expect(firstPage.items, isNotEmpty);
    expect(firstPage.hasMore, isTrue);

    final secondPage = await dataSource.fetchRecommendRooms(page: 2);
    expect(secondPage.items, isNotEmpty);
    expect(
      secondPage.items.map((item) => item.roomId),
      contains('justchatting2'),
    );
    expect(secondPage.page, 2);
    expect(secondPage.hasMore, isTrue);
  });
}

class _FakeTwitchCategoryApiClient implements TwitchApiClient {
  static final List<Map<String, dynamic>> _justChattingStreams =
      List.generate(40, (index) {
    final login = switch (index) {
      0 => 'xqc',
      1 => 'arky',
      _ => 'justchatting$index',
    };
    final displayName = switch (index) {
      0 => 'xQc',
      1 => 'arky',
      _ => 'JustChatting$index',
    };
    return {
      'title': 'Just Chatting Stream #$index',
      'previewImageURL': 'https://static.test/$login.jpg',
      'viewersCount': 20000 - index,
      'broadcaster': {
        'login': login,
        'displayName': displayName,
        'profileImageURL': 'https://static.test/$login-avatar.jpg',
      },
      'game': {
        'id': '509658',
        'slug': 'just-chatting',
        'displayName': 'Just Chatting',
        'boxArtURL': 'https://static.test/{width}x{height}.jpg',
      },
    };
  });

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Object?> postGraphQl(
    Object payload, {
    String deviceId = '',
    String clientSessionId = '',
    String clientIntegrity = '',
  }) async {
    final request = payload as Map<String, dynamic>;
    final operationName = request['operationName']?.toString();
    final variables = request['variables'] as Map<String, dynamic>? ?? const {};
    if (operationName == 'BrowsePage_Popular') {
      return {
        'data': {
          'streams': {
            'edges': _justChattingStreams
                .take(2)
                .map((item) => {'node': item, 'cursor': item['title']})
                .toList(),
            'pageInfo': {
              'hasNextPage': true,
            },
          },
        },
      };
    }
    if (operationName == 'SideNav') {
      return {
        'data': {
          'sideNav': {
            'sections': {
              'edges': [
                {
                  'node': {
                    'content': {
                      'edges': [
                        {
                          'node': {
                            'type': 'LIVE',
                            'viewersCount': 22089,
                            'broadcaster': {
                              'login': 'xqc',
                              'displayName': 'xQc',
                              'profileImageURL':
                                  'https://static.test/xqc-avatar.jpg',
                              'broadcastSettings': {
                                'title': 'LIVE REACT DRAMA NEWS VIDEOS GAMES',
                              },
                            },
                            'game': {
                              'id': '509658',
                              'displayName': 'Just Chatting',
                            },
                          },
                        },
                      ],
                    },
                  },
                },
              ],
            },
          },
        },
      };
    }
    if (operationName == 'BrowsePage_AllDirectories') {
      return {
        'data': {
          'directoriesWithTags': {
            'edges': [
              {
                'cursor': 'page-1',
                'node': {
                  'id': '509658',
                  'slug': 'just-chatting',
                  'displayName': 'Just Chatting',
                  'avatarURL': 'https://static.test/{width}x{height}.jpg',
                },
              },
              {
                'cursor': 'page-2',
                'node': {
                  'id': '21779',
                  'slug': 'league-of-legends',
                  'displayName': 'League of Legends',
                  'boxArtURL': 'https://static.test/lol-{width}x{height}.jpg',
                },
              },
              {
                'cursor': 'page-3',
                'node': {
                  'id': '32982',
                  'slug': 'grand-theft-auto-v',
                  'displayName': 'Grand Theft Auto V',
                  'boxArtURL': 'https://static.test/gta-{width}x{height}.jpg',
                },
              },
            ],
            'pageInfo': {
              'hasNextPage': true,
            },
          },
        },
      };
    }
    if (operationName == 'DirectoryPage_Game') {
      final slug = variables['slug']?.toString();
      final limit = variables['limit'] as int? ?? 30;
      if (slug != 'just-chatting') {
        return {
          'data': {
            'game': {
              'streams': {
                'edges': const [],
                'pageInfo': {
                  'hasNextPage': false,
                },
              },
            },
          },
        };
      }
      final items = _justChattingStreams.take(limit).toList(growable: false);
      return {
        'data': {
          'game': {
            'streams': {
              'edges': items.map((item) => {'node': item}).toList(),
              'pageInfo': {
                'hasNextPage': limit < _justChattingStreams.length,
              },
            },
          },
        },
      };
    }
    throw UnimplementedError('Unexpected Twitch operation: $operationName');
  }
}

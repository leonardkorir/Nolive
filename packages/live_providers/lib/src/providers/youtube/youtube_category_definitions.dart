class YouTubeLiveCategoryDefinition {
  const YouTubeLiveCategoryDefinition({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.name,
    required this.queries,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String name;
  final List<String> queries;
}

const List<YouTubeLiveCategoryDefinition> youtubeCategoryDefinitions = [
  YouTubeLiveCategoryDefinition(
    id: 'news',
    groupId: 'content',
    groupName: '内容分类',
    name: '新闻',
    queries: [
      'live news',
      'breaking news live',
      'world news live',
      'politics live',
      'financial news live',
    ],
  ),
  YouTubeLiveCategoryDefinition(
    id: 'gaming',
    groupId: 'content',
    groupName: '内容分类',
    name: '游戏',
    queries: [
      'gaming live',
      'esports live',
      'valorant live',
      'league of legends live',
      'minecraft live',
    ],
  ),
  YouTubeLiveCategoryDefinition(
    id: 'music',
    groupId: 'content',
    groupName: '内容分类',
    name: '音乐',
    queries: [
      'music live',
      'live concert',
      'dj live',
      'lofi live',
      'radio live',
    ],
  ),
  YouTubeLiveCategoryDefinition(
    id: 'entertainment',
    groupId: 'content',
    groupName: '内容分类',
    name: '娱乐',
    queries: [
      'entertainment live',
      'talk show live',
      'reaction live',
      'variety show live',
      'vtuber live',
    ],
  ),
  YouTubeLiveCategoryDefinition(
    id: 'sports',
    groupId: 'content',
    groupName: '内容分类',
    name: '体育',
    queries: [
      'sports live',
      'football live',
      'basketball live',
      'baseball live',
      'mma live',
    ],
  ),
  YouTubeLiveCategoryDefinition(
    id: 'podcast',
    groupId: 'content',
    groupName: '内容分类',
    name: '播客',
    queries: [
      'podcast live',
      'talk podcast live',
      'interview live',
      'debate live',
      'talk radio live',
    ],
  ),
];

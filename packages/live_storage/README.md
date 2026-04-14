# live_storage

本地持久化与 repository 层。

## 当前职责

- 文件型 snapshot 顶层持久化
- follow / history / settings / tag repository 契约
- file / in-memory repository 实现
- 顶层 `format_version` 文件格式

## 当前导出面

- `FileStorageSnapshot`、`LocalStorageFileStore`
- `FollowRepository`、`HistoryRepository`、`SettingsRepository`、`TagRepository`
- `File*Repository` 与 `InMemory*Repository`
- `FollowRecord`、`HistoryRecord`

## 当前边界

- 本包负责本地持久化与 repository 实现。
- snapshot 版本属于顶层文件格式，不挂在单个 repository 上。
- 敏感凭证不在本包管理，当前由 app 层 secure store 处理。

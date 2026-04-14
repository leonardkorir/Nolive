# live_sync

同步与备份基础设施层。

## 当前职责

- snapshot model / codec / category
- repository snapshot service
- WebDAV backup / restore
- local discovery / sync client / sync server

## 当前导出面

- `SyncSnapshot`、`SyncSnapshotJsonCodec`、`SyncDataCategory`
- `RepositorySyncSnapshotService`
- `WebDavBackupService`
- `LocalDiscoveryService`、`LocalSyncClient`、`LocalSyncServer`

## 当前边界

- 本包承载日常 snapshot 传输与备份恢复能力。
- 常规同步链路传的是 snapshot，而不是整机存储 dump。
- 敏感凭证过滤与 secure store 分层由 app 层负责。

# live_sync

同步与备份基础设施层。

## 当前职责

- snapshot model / codec / category（顶层 `format_version`，当前 codec 版本 **3**）
- repository snapshot service
- WebDAV backup / restore
- local discovery / sync client / sync server（分类推送；支持 batch fallback）

## 当前导出面

- `SyncSnapshot`、`SyncSnapshotJsonCodec`、`SyncDataCategory`
- `RepositorySyncSnapshotService`
- `WebDavBackupService`
- `LocalDiscoveryService`、`LocalSyncClient`、`LocalSyncServer`

## 当前边界

- 本包承载日常 snapshot 传输与备份恢复能力，不是云级配对同步产品。
- 常规同步链路传的是 snapshot，而不是整机存储 dump。
- 敏感凭证过滤、secure store、受控迁移包与 LAN opt-in 凭证附带由 **app 层**负责。

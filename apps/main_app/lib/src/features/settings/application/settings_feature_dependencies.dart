import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';

import 'credential_migration_bundle.dart';
import 'manage_provider_accounts_use_case.dart';
import 'manage_snapshot_data_use_case.dart';

class SettingsFeatureDependencies {
  const SettingsFeatureDependencies({
    required this.loadProviderAccountDashboard,
    required this.updateProviderAccountSettings,
    required this.createBilibiliQrLoginSession,
    required this.pollBilibiliQrLoginSession,
    required this.clearProviderAccount,
    required this.exportLegacyConfigJson,
    required this.exportSyncSnapshotJson,
    required this.importSyncSnapshotJson,
    required this.exportCredentialMigrationBundle,
    required this.importCredentialMigrationBundle,
    required this.resetAppData,
    required this.clearSensitiveCredentials,
  });

  factory SettingsFeatureDependencies.fromBootstrap(AppBootstrap bootstrap) {
    return SettingsFeatureDependencies(
      loadProviderAccountDashboard: bootstrap.loadProviderAccountDashboard,
      updateProviderAccountSettings: bootstrap.updateProviderAccountSettings,
      createBilibiliQrLoginSession: bootstrap.createBilibiliQrLoginSession,
      pollBilibiliQrLoginSession: bootstrap.pollBilibiliQrLoginSession,
      clearProviderAccount: bootstrap.clearProviderAccount,
      exportLegacyConfigJson: bootstrap.exportLegacyConfigJson,
      exportSyncSnapshotJson: bootstrap.exportSyncSnapshotJson,
      importSyncSnapshotJson: bootstrap.importSyncSnapshotJson,
      exportCredentialMigrationBundle:
          bootstrap.exportCredentialMigrationBundle,
      importCredentialMigrationBundle:
          bootstrap.importCredentialMigrationBundle,
      resetAppData: bootstrap.resetAppData,
      clearSensitiveCredentials: bootstrap.clearSensitiveCredentials,
    );
  }

  final LoadProviderAccountDashboardUseCase loadProviderAccountDashboard;
  final UpdateProviderAccountSettingsUseCase updateProviderAccountSettings;
  final CreateBilibiliQrLoginSessionUseCase createBilibiliQrLoginSession;
  final PollBilibiliQrLoginSessionUseCase pollBilibiliQrLoginSession;
  final ClearProviderAccountUseCase clearProviderAccount;
  final ExportLegacyConfigJsonUseCase exportLegacyConfigJson;
  final ExportSyncSnapshotJsonUseCase exportSyncSnapshotJson;
  final ImportSyncSnapshotJsonUseCase importSyncSnapshotJson;
  final ExportCredentialMigrationBundleUseCase exportCredentialMigrationBundle;
  final ImportCredentialMigrationBundleUseCase importCredentialMigrationBundle;
  final ResetAppDataUseCase resetAppData;
  final ClearSensitiveCredentialsUseCase clearSensitiveCredentials;
}

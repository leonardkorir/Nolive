import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_providers/live_providers.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nolive_app/src/features/settings/application/settings_feature_dependencies.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';

class BilibiliQrLoginPage extends StatefulWidget {
  const BilibiliQrLoginPage({required this.dependencies, super.key});

  final SettingsFeatureDependencies dependencies;

  @override
  State<BilibiliQrLoginPage> createState() => _BilibiliQrLoginPageState();
}

class _BilibiliQrLoginPageState extends State<BilibiliQrLoginPage> {
  BilibiliQrLoginSession? _session;
  Object? _error;
  String _statusMessage = '正在获取二维码…';
  Timer? _pollTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _session = null;
      _statusMessage = '正在获取二维码…';
    });
    try {
      final session = await widget.dependencies.createBilibiliQrLoginSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _busy = false;
        _statusMessage = '请使用哔哩哔哩客户端扫码确认';
      });
      _pollTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _pollSession(),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _pollSession() async {
    final session = _session;
    if (session == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final progress = await widget.dependencies.pollBilibiliQrLoginSession(
        session.qrcodeKey,
      );
      if (!mounted) {
        return;
      }
      switch (progress.status) {
        case BilibiliQrLoginStatus.pending:
          setState(() {
            _busy = false;
            _statusMessage = '等待扫码…';
          });
        case BilibiliQrLoginStatus.scanned:
          setState(() {
            _busy = false;
            _statusMessage = '已扫码，请在手机上确认登录';
          });
        case BilibiliQrLoginStatus.expired:
          _pollTimer?.cancel();
          setState(() {
            _busy = false;
            _statusMessage = '二维码已失效，请刷新';
          });
        case BilibiliQrLoginStatus.success:
          _pollTimer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已登录 ${progress.displayName ?? '哔哩哔哩账号'}${progress.userId == null ? '' : ' · UID ${progress.userId}'}',
              ),
            ),
          );
          Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _pollTimer?.cancel();
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('哔哩哔哩扫码登录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '扫码登录',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '使用哔哩哔哩手机客户端扫描二维码。登录成功后会自动写入 Cookie 和 UID。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            EmptyStateCard(
              title: '二维码加载失败',
              message: '$_error',
              icon: Icons.qr_code_2,
            )
          else if (_session == null)
            const AppSurfaceCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            )
          else
            AppSurfaceCard(
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: QrImageView(
                        data: _session!.qrcodeUrl,
                        backgroundColor: Colors.white,
                        size: 220,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '如果二维码失效，可以重新生成一张新的二维码继续登录。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _startSession,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新二维码'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close),
                label: const Text('暂不登录'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

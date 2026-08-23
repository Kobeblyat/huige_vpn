part of desktop_subscription_screen;

/// 订阅管理页面 - 桌面优化
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _urlController = TextEditingController();
  bool _isAdding = false;
  bool _isRefreshing = false;
  bool _isDeleting = false;
  SubscriptionRefreshResult? _refreshResult;
  SubscriptionRefreshCancellation? _refreshCancellation;

  bool get _hasBlockingOperation => _isAdding || _isRefreshing || _isDeleting;

  List<SsrvpnSupportLink> get _supportLinks => [
        SsrvpnSupportLink(
          title: '检查更新',
          subtitle: 'GitHub 自动更新',
          icon: Icons.system_update_alt_rounded,
          url: 'action:check_update',
          primaryColor: AppTheme.primary,
        ),
        SsrvpnSupportLink(
          title: '更新镜像源',
          subtitle: '切换 GitHub 加速源',
          icon: Icons.speed_rounded,
          url: 'action:change_mirror',
          primaryColor: AppTheme.success,
        ),
        SsrvpnSupportLink(
          title: '官网',
          subtitle: '灰哥VPN 官方网站',
          icon: Icons.language_rounded,
          url: AppConstants.officialWebsiteUrl,
          primaryColor: AppTheme.primary,
        ),
        SsrvpnSupportLink(
          title: '购买套餐',
          subtitle: '查看套餐并购买',
          icon: Icons.storefront_rounded,
          url: AppConstants.purchasePlanUrl,
          primaryColor: AppTheme.success,
        ),
        SsrvpnSupportLink(
          title: '在线客服',
          subtitle: '实时咨询',
          icon: Icons.headset_mic_rounded,
          url: AppConstants.onlineSupportUrl,
          primaryColor: AppTheme.accentColor,
        ),
        SsrvpnSupportLink(
          title: '提交工单',
          subtitle: '提交问题与建议',
          icon: Icons.assignment_outlined,
          url: AppConstants.submitTicketUrl,
          primaryColor: AppTheme.warning,
        ),
      ];

  Future<void> _openSupportLink(SsrvpnSupportLink link) async {
    final url = link.url.trim();
    if (url.isEmpty) return;
    if (url == 'action:check_update') {
      await _manualCheckUpdate();
      return;
    }
    if (url == 'action:change_mirror') {
      await _showMirrorDialog();
      return;
    }
    try {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } catch (e) {
      if (!mounted) return;
      _showSnack('无法打开链接：$e', AppTheme.error);
    }
  }

  Future<void> _manualCheckUpdate() async {
    _showSnack('正在检查 GitHub 更新...', AppTheme.primary, duration: const Duration(seconds: 2));
    try {
      final settingsService = context.read<SettingsService>();
      final mirrorUrl = settingsService.settings.githubMirrorUrl;
      final update = await UpdateService.checkForUpdate(
        AppConstants.appVersion,
        mirrorUrl: mirrorUrl,
      );
      if (!mounted) return;
      if (update != null) {
        await UpdateService.showUpdateDialog(
          context,
          latestVersion: update.version,
          currentVersion: AppConstants.appVersion,
          downloadUrl: update.downloadUrl,
          changelog: update.changelog,
          sha256: update.sha256,
          fallbackDownloadUrl: update.fallbackDownloadUrl,
        );
      } else {
        _showSnack('当前已是最新版本 (v${AppConstants.appVersion})', AppTheme.success);
      }
    } catch (e) {
      if (mounted) _showSnack('检查更新失败：$e', AppTheme.error);
    }
  }

  Future<void> _showMirrorDialog() async {
    final settingsService = context.read<SettingsService>();
    var selected = settingsService.settings.githubMirrorUrl;
    final customCtrl = TextEditingController(
      text: AppConstants.githubMirrors.any((m) => m['url'] == selected) ? '' : selected,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('GitHub 更新加速源设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择或输入用于加速下载 GitHub Releases 更新包的镜像站：', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                ...AppConstants.githubMirrors.map((m) {
                  final name = m['name']!;
                  final url = m['url']!;
                  return RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(url.isNotEmpty ? url : '不使用加速镜像', style: const TextStyle(fontSize: 11)),
                    value: url,
                    groupValue: selected,
                    onChanged: (val) {
                      setDialogState(() {
                        selected = val ?? '';
                        customCtrl.clear();
                      });
                    },
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(
                    labelText: '自定义镜像前缀 (例如: https://ghproxy.net/)',
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setDialogState(() {
                      selected = val.trim();
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final mirror = customCtrl.text.trim().isNotEmpty
                    ? customCtrl.text.trim()
                    : selected;
                await settingsService.updateGithubMirrorUrl(mirror);
                if (mounted) {
                  Navigator.pop(dialogCtx);
                  _showSnack('已保存更新镜像源设置', AppTheme.success);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _refreshCancellation?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addSubscription() async {
    if (_hasBlockingOperation) return;
    setState(() => _isAdding = true);
    final controller = _subscriptionController(
      context.read<SubscriptionService>(),
    );
    final result = await controller.addSubscription(_urlController.text);
    if (!mounted) return;

    if (result.clearInput) _urlController.clear();
    _showAddResult(result);
    setState(() => _isAdding = false);
  }

  Future<void> _refreshAll() async {
    if (_hasBlockingOperation) return;
    final cancellation = SubscriptionRefreshCancellation();
    _refreshCancellation = cancellation;
    setState(() {
      _isRefreshing = true;
      _refreshResult = null;
    });

    final controller = _subscriptionController(
      context.read<SubscriptionService>(),
    );
    final result = await controller.refreshAll(cancellation: cancellation);
    if (!mounted || !identical(_refreshCancellation, cancellation)) return;

    setState(() {
      _refreshCancellation = null;
      _refreshResult = result;
      _isRefreshing = false;
    });
    if (result.shouldShowNetworkHelp) {
      _showNetworkErrorDialog(result.networkErrorDetail!);
    }
  }

  void _cancelRefresh() {
    _refreshCancellation?.cancel();
  }

  SubscriptionScreenController _subscriptionController(
    SubscriptionService subService,
  ) {
    return SubscriptionScreenController(
      subscriptionService: CallbackSubscriptionScreenService(
        subscriptionsOf: () => subService.subscriptions,
        allNodesOf: () => subService.allNodes,
        allGroupsOf: () => subService.allGroups,
        isSingleNodeLinkOf: subService.isSingleNodeLink,
        defaultSubscriptionNameOf: subService.defaultSubscriptionName,
        addSubscriptionWith: subService.addSubscription,
        refreshAllSubscriptionsDetailedWith:
            subService.refreshAllSubscriptionsDetailed,
        removeSubscriptionWith: subService.removeSubscription,
      ),
    );
  }

  void _showAddResult(SubscriptionAddResult result) {
    switch (result.status) {
      case SubscriptionAddStatus.emptyInput:
        _showSnack(
          '请输入订阅链接或SSR链接',
          AppTheme.error,
          behavior: SnackBarBehavior.floating,
        );
      case SubscriptionAddStatus.duplicate:
        _showSnack('该订阅已存在，无需重复添加', AppTheme.warning);
      case SubscriptionAddStatus.invalidUrl:
        _showSnack('请输入有效的URL地址', AppTheme.error);
      case SubscriptionAddStatus.singleNodeImported:
        _showSnack('SSR链接已导入，当前共 ${result.nodeCount} 个节点', AppTheme.success);
      case SubscriptionAddStatus.singleNodeNoData:
        _showSnack('SSR链接已添加，但未获取到数据', AppTheme.warning);
      case SubscriptionAddStatus.singleNodeImportFailed:
        _showSnack('导入失败: ${result.displayError}', AppTheme.error);
      case SubscriptionAddStatus.subscriptionAdded:
        _showSnack('订阅成功，获取到 ${result.nodeCount} 个节点', AppTheme.success);
      case SubscriptionAddStatus.subscriptionNoData:
        _showSnack('订阅已添加，但未获取到数据', AppTheme.warning);
      case SubscriptionAddStatus.refreshFailed:
        _showSnack(
          '刷新失败: ${result.displayError}',
          AppTheme.error,
          duration: const Duration(seconds: 4),
        );
      case SubscriptionAddStatus.failed:
        _showSnack('添加失败: ${result.displayError}', AppTheme.error);
    }
  }

  void _showSnack(
    String message,
    Color backgroundColor, {
    Duration? duration,
    SnackBarBehavior? behavior,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: behavior,
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  void _showNetworkErrorDialog(String detail) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => SsrvpnSubscriptionErrorDialog(detail: detail),
    );
  }

  Future<void> _deleteSubscription(String id) async {
    if (_hasBlockingOperation) return;
    setState(() => _isDeleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.88),
            child: GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '确认删除',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '删除后将无法恢复',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 120 / 255)
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error,
                          ),
                          child: const Text('删除'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (confirmed == true) {
        if (!mounted) return;
        final subService = context.read<SubscriptionService>();
        final clashService = context.read<ClashService>();
        final result =
            await _subscriptionController(subService).deleteSubscription(
          id,
          clashRunning:
              clashService.isRunning || clashService.connectionDesired,
          stopClash: () async {
            clashService.requestConnectionIntent(false);
            clashService.interruptPendingStart();
            await clashService.runConnectionTransition(clashService.stop);
          },
        ).catchError((Object e) {
          return SubscriptionDeleteResult(removed: false, error: e);
        });
        if (!mounted) return;

        if (!result.removed) {
          _showSnack(
            '删除失败：${result.displayError}',
            AppTheme.error,
          );
        } else if (result.error != null) {
          _showSnack(
            '订阅已删除，但断开 VPN 失败：${result.displayError}',
            AppTheme.warning,
          );
        } else if (result.stoppedClash) {
          _showSnack('订阅已删除，VPN 已断开', AppTheme.warning);
        } else {
          _showSnack('订阅已删除', AppTheme.success);
        }
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subService = context.watch<SubscriptionService>();
    final refreshResult = _refreshResult;
    final refreshColor = switch (refreshResult?.status) {
      SubscriptionRefreshStatus.success => SsrvpnUiTokens.success,
      SubscriptionRefreshStatus.partialSuccess => SsrvpnUiTokens.warning,
      SubscriptionRefreshStatus.failure => SsrvpnUiTokens.error,
      SubscriptionRefreshStatus.cancelled => SsrvpnUiTokens.textSecondary,
      null => null,
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SsrvpnSubscriptionView(
        subscriptions: subService.subscriptions,
        urlController: _urlController,
        isAdding: _isAdding,
        isRefreshing: _isRefreshing,
        isBusy: _hasBlockingOperation,
        refreshMessage: refreshResult?.message,
        refreshMessageColor: refreshColor,
        supportLinks: _supportLinks,
        onOpenSupport: _openSupportLink,
        onAdd: _addSubscription,
        onRefresh: _refreshAll,
        onCancelRefresh: _cancelRefresh,
        onDelete: _deleteSubscription,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

/// 账号登录弹窗（灰哥VPN 专版）
///
/// 展示当前登录状态，并提供登录表单。登录成功后自动拉取订阅地址并导入。
/// 面板体系与手机版一致：email + password → passport/auth/login →
/// user/getSubscribe → sub.php 订阅导入。
class AccountLoginDialog extends StatefulWidget {
  const AccountLoginDialog({super.key});

  @override
  State<AccountLoginDialog> createState() => _AccountLoginDialogState();
}

class _AccountLoginDialogState extends State<AccountLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoggingIn = false;
  bool _isImporting = false;
  String? _error;
  String? _success;

  AccountService get _account =>
      context.read<AccountService>();

  @override
  void initState() {
    super.initState();
    final email = _account.email;
    if (email != null && email.isNotEmpty) {
      _emailController.text = email;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoggingIn || _isImporting) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }
    setState(() {
      _isLoggingIn = true;
      _error = null;
      _success = null;
    });

    final account = _account;
    final result = await account.login(email, password);
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _isLoggingIn = false;
        _error = result.error;
      });
      return;
    }

    setState(() {
      _isLoggingIn = false;
      _success = '登录成功，正在获取订阅...';
      _isImporting = true;
    });

    await _doImport();
  }

  Future<void> _doImport() async {
    final account = _account;
    final subService = context.read<SubscriptionService>();
    try {
      // v2board 面板校验：未购买套餐或套餐已到期时阻止导入节点。
      final userInfo = await account.fetchUserInfo();
      if (!mounted) return;
      if (!userInfo.hasActivePlan) {
        setState(() {
          _isImporting = false;
          _error = userInfo.isExpired
              ? '套餐已到期，请续费后再使用'
              : '您还没有购买套餐，请先购买后再使用';
        });
        _showPurchasePlanHint();
        return;
      }

      final subscribeUrl = await account.fetchSubscriptionUrl();
      final existing = subService.subscriptions
          .where((s) => s.url == subscribeUrl)
          .toList();
      if (existing.isEmpty) {
        await subService.addSubscription('灰哥VPN', subscribeUrl);
      }

      await subService.refreshAllSubscriptions();
      final nodes = subService.allNodes;

      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _success = nodes.isEmpty
            ? '订阅已导入，但未获取到可用节点'
            : '订阅已获取，共 ${nodes.length} 个节点，请回到首页选择节点连接';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _error = '$e';
      });
    }
  }

  void _showPurchasePlanHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请前往官网购买套餐后返回重新获取订阅'),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _logout() async {
    if (_isLoggingIn || _isImporting) return;
    await _account.logout();
    if (!mounted) return;
    setState(() {
      _error = null;
      _success = null;
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _account.isLoggedIn;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(24),
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_circle_rounded,
                  size: 30,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '账号登录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '登录后自动获取订阅节点',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
const SizedBox(height: 18),
        if (loggedIn) _buildLoggedIn(),
        if (!loggedIn) _buildLogin(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedIn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前账号',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _account.email ?? '--',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              _success!,
              style: const TextStyle(color: AppTheme.success, fontSize: 13),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isImporting ? null : _doImport,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('重新获取订阅'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _isImporting ? null : _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('退出登录'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '完成',
              style: TextStyle(color: AppTheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('account-login-email'),
          controller: _emailController,
          enabled: !_isLoggingIn,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '邮箱',
            hintText: '请输入账号邮箱',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('account-login-password'),
          controller: _passwordController,
          enabled: !_isLoggingIn,
          obscureText: _obscure,
          onSubmitted: _isLoggingIn ? null : (_) => _submit(),
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '请输入密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoggingIn ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoggingIn
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '登录',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              // 打开面板官网 / 注册入口
              _showRegisterHint();
            },
            child: const Text(
              '还没有账号？去注册',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  void _showRegisterHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请前往灰哥VPN 官网注册账号后返回登录'),
        backgroundColor: AppTheme.textSecondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
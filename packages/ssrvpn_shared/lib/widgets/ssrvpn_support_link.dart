import 'package:flutter/material.dart';

/// 订阅页「服务支持」入口项。
class SsrvpnSupportLink {
  const SsrvpnSupportLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.url,
    this.primaryColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String url;
  final Color? primaryColor;
}

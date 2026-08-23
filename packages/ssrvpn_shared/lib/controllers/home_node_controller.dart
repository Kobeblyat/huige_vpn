import '../models/proxy_node.dart';
import '../utils/node_display_policy.dart';
import '../utils/proxy_node_usage_policy.dart';
import '../utils/runtime_config_name_policy.dart';

class HomeNodeSyncResult {
  const HomeNodeSyncResult({
    required this.changed,
    required this.isFirstSync,
    required this.hasNodes,
  });

  final bool changed;
  final bool isFirstSync;
  final bool hasNodes;

  bool get shouldPromptForImport => changed && !hasNodes;
}

class HomeNodeController {
  HomeNodeController({
    Iterable<ProxyNode> nodes = const [],
    this.lastRevision = -1,
  }) : nodes = runnableNodesFrom(nodes);

  List<ProxyNode> nodes;
  int lastRevision;

  HomeNodeSyncResult syncSubscriptionSnapshot({
    required int revision,
    required Iterable<ProxyNode> allNodes,
  }) {
    if (revision == lastRevision) {
      return HomeNodeSyncResult(
        changed: false,
        isFirstSync: false,
        hasNodes: nodes.isNotEmpty,
      );
    }

    final isFirstSync = lastRevision == -1;
    lastRevision = revision;
    nodes = runnableNodesFrom(allNodes);
    return HomeNodeSyncResult(
      changed: true,
      isFirstSync: isFirstSync,
      hasNodes: nodes.isNotEmpty,
    );
  }

  /// The virtual "auto" selection shown in the node list. It maps to the
  /// `自动选择` url-test group in the runtime config, which continuously
  /// probes members and picks the lowest-latency one without user action.
  static String get autoSelectNodeName =>
      RuntimeConfigNamePolicy.standardGroupNames
          .firstWhere((name) => name.contains('自动'));

  static ProxyNode autoSelectNode() => ProxyNode(
        name: autoSelectNodeName,
        type: 'auto',
        server: '',
        port: 0,
        group: '',
      );

  static bool isAutoSelectNodeName(String? name) =>
      name != null && name == autoSelectNodeName;

  static ProxyNode? resolveDefaultNodeFrom(
    Iterable<ProxyNode> nodes,
    String? rememberedNodeName,
  ) {
    final runnable = runnableNodesFrom(nodes);
    if (rememberedNodeName != null && rememberedNodeName.isNotEmpty) {
      if (isAutoSelectNodeName(rememberedNodeName)) return autoSelectNode();
      for (final node in runnable) {
        // A user can deliberately preselect an offline/timed-out node. Keep
        // that intent for the next connection; latency only guides fallback.
        if (node.name == rememberedNodeName) return node;
      }
    }
    if (runnable.isEmpty) return null;
    // The auto-select url-test group is the default selection: it keeps
    // routing through the lowest-latency member without manual switching.
    return autoSelectNode();
  }

  static ProxyNode? resolveRuntimeSelectedNodeFrom(
    Iterable<ProxyNode> nodes,
    String? runtimeNodeName,
  ) {
    final name = runtimeNodeName?.trim();
    if (name == null || name.isEmpty) return null;
    if (isAutoSelectNodeName(name)) return autoSelectNode();
    for (final node in runnableNodesFrom(nodes)) {
      if (node.name == name) return node;
    }
    return null;
  }

  static List<ProxyNode> runnableNodesFrom(Iterable<ProxyNode> nodes) {
    return nodes
        .where(ProxyNodeUsagePolicy.isRunnableNode)
        .toList(growable: false);
  }

  static void applyLatenciesTo(
    Iterable<ProxyNode> nodes,
    Map<String, int> latencies,
    Map<String, int> batch, {
    DateTime? testedAt,
  }) {
    if (batch.isEmpty) return;
    latencies.addAll(batch);
    final now = testedAt ?? DateTime.now();
    for (final node in nodes) {
      final latency = batch[node.name];
      if (latency == null) continue;
      node.latency = latency;
      node.lastLatencyTest = now;
    }
  }

  static bool canSelectNode(
    ProxyNode node,
    Map<String, int> latencies,
  ) {
    return NodeDisplayPolicy.isSelectableLatency(
          latencies[node.name] ?? node.latency,
        ) &&
        ProxyNodeUsagePolicy.isRunnableNode(node);
  }

  static List<ProxyNode> timeoutLast(
    Iterable<ProxyNode> nodes,
    Map<String, int> latencies,
  ) {
    return NodeDisplayPolicy.timeoutLast(
      nodes,
      latencyOf: (node) => latencies[node.name] ?? node.latency,
    );
  }
}

import 'dart:async';

enum RuntimeLogLevel { info, warning, error, debug }
enum RuntimeNoticeLevel { progress, success, error, warning, info }

class RuntimeNotice {
  const RuntimeNotice(this.message, {this.level = RuntimeNoticeLevel.info});
  const RuntimeNotice.progress(this.message) : level = RuntimeNoticeLevel.progress;
  const RuntimeNotice.success(this.message) : level = RuntimeNoticeLevel.success;
  const RuntimeNotice.error(this.message) : level = RuntimeNoticeLevel.error;
  const RuntimeNotice.warning(this.message) : level = RuntimeNoticeLevel.warning;
  const RuntimeNotice.info(this.message) : level = RuntimeNoticeLevel.info;

  final String message;
  final RuntimeNoticeLevel level;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeNotice &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          level == other.level;

  @override
  int get hashCode => Object.hash(message, level);

  @override
  String toString() => 'RuntimeNotice($level: $message)';
}

const coreAutoRecoveredRuntimeNotice = RuntimeNotice.success('核心已自动恢复');
const runtimeNoticeSuccessDuration = Duration(seconds: 3);
const windowsTunElevationHandoffRuntimeNotice = RuntimeNotice.progress(
  '管理员授权已通过。灰哥VPN 将暂时关闭当前窗口，并自动以管理员模式重新打开、继续连接 TUN；'
  '请耐心等待，不要重复启动软件。',
);
const windowsTunElevationHandoffNoticeDuration = Duration(seconds: 3);

bool isSuccessfulRuntimeNotice(RuntimeNotice? notice) =>
    notice?.level == RuntimeNoticeLevel.success || notice == coreAutoRecoveredRuntimeNotice;

bool isInProgressRuntimeNotice(RuntimeNotice? notice) =>
    notice?.level == RuntimeNoticeLevel.progress || notice == windowsTunElevationHandoffRuntimeNotice;

bool shouldClearRuntimeNoticeOnRunningEdge({
  required bool wasRunning,
  required bool isRunning,
  required RuntimeNotice? notice,
}) {
  if (!wasRunning && isRunning && notice != null) {
    return notice.level == RuntimeNoticeLevel.error;
  }
  return false;
}

Timer? scheduleSuccessfulRuntimeNoticeClear({
  required RuntimeNotice notice,
  required RuntimeNotice? Function() currentNotice,
  required void Function() clear,
  Duration delay = runtimeNoticeSuccessDuration,
}) {
  if (!isSuccessfulRuntimeNotice(notice)) return null;

  return Timer(delay, () {
    if (currentNotice() == notice) clear();
  });
}

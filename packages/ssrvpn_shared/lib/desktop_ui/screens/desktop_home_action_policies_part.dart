part of desktop_home_screen;

bool desktopStatusNotificationChangesState({
  required bool wasConnected,
  required bool isRunning,
  required String? previousWarning,
  required String? nextWarning,
  required bool cancelledWhileConnecting,
}) {
  if (wasConnected != isRunning) return true;
  if (previousWarning != nextWarning) return true;
  if (cancelledWhileConnecting) return true;
  return false;
}

String? desktopConnectionCancellationNotice({
  required bool stopSucceeded,
  required bool isRunning,
}) {
  if (stopSucceeded && !isRunning) {
    return '连接已取消';
  }
  return null;
}

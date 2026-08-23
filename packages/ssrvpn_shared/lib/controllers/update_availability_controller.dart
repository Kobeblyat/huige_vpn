import 'package:flutter/foundation.dart';
import '../services/update_checker.dart';

class UpdateAvailabilityController extends ChangeNotifier {
  AppUpdateInfo? _updateInfo;
  bool _dismissed = false;

  AppUpdateInfo? get updateInfo => _dismissed ? null : _updateInfo;
  bool get hasUpdate => updateInfo != null;

  void setUpdate(AppUpdateInfo? info) {
    _updateInfo = info;
    _dismissed = false;
    notifyListeners();
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }
}

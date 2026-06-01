import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  String _activeLocationId = '';
  String _activeLocationName = '我的家';

  String get activeLocationId => _activeLocationId;
  String get activeLocationName => _activeLocationName;

  void setActiveLocation(String id, String name) {
    _activeLocationId = id;
    _activeLocationName = name;
    notifyListeners();
  }
}

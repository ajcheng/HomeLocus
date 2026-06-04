import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  String _token = '';
  String _activeLocationId = '';
  String _activeLocationName = '我的家';
  Map<String, dynamic>? _user;
  int _searchListVersion = 0;
  int _homeTabIndex = 0;
  String? _focusSlotId;

  String get token => _token;
  String get activeLocationId => _activeLocationId;
  String get activeLocationName => _activeLocationName;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token.isNotEmpty;
  int get searchListVersion => _searchListVersion;
  int get homeTabIndex => _homeTabIndex;
  String? get focusSlotId => _focusSlotId;

  void refreshSearchItems() {
    _searchListVersion++;
    notifyListeners();
  }

  void login(String token, Map<String, dynamic> user) {
    _token = token;
    _user = user;
    notifyListeners();
  }

  void logout() {
    _token = '';
    _user = null;
    notifyListeners();
  }

  void setActiveLocation(String id, String name) {
    _activeLocationId = id;
    _activeLocationName = name;
    notifyListeners();
  }

  /// Switch to space tab and expand tree to the given slot.
  void openSlotInSpace(String slotId) {
    _focusSlotId = slotId;
    _homeTabIndex = 0;
    notifyListeners();
  }

  void setHomeTabIndex(int index) {
    _homeTabIndex = index;
    notifyListeners();
  }

  void clearFocusSlot() {
    _focusSlotId = null;
  }
}

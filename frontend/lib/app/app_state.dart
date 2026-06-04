import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  String _token = '';
  String _activeLocationId = '';
  String _activeLocationName = '我的家';
  Map<String, dynamic>? _user;
  int _searchListVersion = 0;
  int _homeTabIndex = 0;
  String? _focusSlotId;
  String? _focusZoneId;

  String get token => _token;
  String get activeLocationId => _activeLocationId;
  String get activeLocationName => _activeLocationName;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token.isNotEmpty;
  int get searchListVersion => _searchListVersion;
  int get homeTabIndex => _homeTabIndex;
  String? get focusSlotId => _focusSlotId;
  String? get focusZoneId => _focusZoneId;

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
    _focusZoneId = null;
    _homeTabIndex = 0;
    notifyListeners();
  }

  /// Switch to space tab and expand the given zone (from floor plan).
  void openFamilyLocation(String locationId, String locationName) {
    setActiveLocation(locationId, locationName);
    _homeTabIndex = 0;
    notifyListeners();
  }

  void openZoneInSpace(String zoneId, {String? locationId, String? locationName}) {
    _focusZoneId = zoneId;
    _focusSlotId = null;
    _homeTabIndex = 0;
    if (locationId != null && locationId.isNotEmpty) {
      _activeLocationId = locationId;
      if (locationName != null) _activeLocationName = locationName;
    }
    notifyListeners();
  }

  void setHomeTabIndex(int index) {
    _homeTabIndex = index;
    notifyListeners();
  }

  void clearFocusSlot() {
    _focusSlotId = null;
  }

  void clearFocusZone() {
    _focusZoneId = null;
  }
}

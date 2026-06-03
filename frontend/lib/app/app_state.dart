import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  String _token = '';
  String _activeLocationId = '';
  String _activeLocationName = '我的家';
  Map<String, dynamic>? _user;
  int _searchListVersion = 0;

  String get token => _token;
  String get activeLocationId => _activeLocationId;
  String get activeLocationName => _activeLocationName;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token.isNotEmpty;
  int get searchListVersion => _searchListVersion;

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
}

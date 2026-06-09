import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../services/settings_service.dart';
import '../services/space_repository.dart';

class AppState extends ChangeNotifier {
  final settings = SettingsService();
  final spaceRepo = SpaceRepository();

  AppConfig config = AppConfig();
  String? activeLocationId;
  bool initialized = false;
  int revision = 0;

  Future<void> init() async {
    config = await settings.load();
    await spaceRepo.ensureSeedData();
    final locs = await spaceRepo.listLocations();
    activeLocationId = locs.isNotEmpty ? locs.first['id'] as String : null;
    initialized = true;
    notifyListeners();
  }

  Future<void> saveConfig(AppConfig c) async {
    config = c;
    await settings.save(c);
    notifyListeners();
  }

  void bump() {
    revision++;
    notifyListeners();
  }

  Future<void> setActiveLocation(String locationId) async {
    activeLocationId = locationId;
    await spaceRepo.setDefaultLocation(locationId);
    bump();
  }

  void clearActiveLocation() {
    activeLocationId = null;
    bump();
  }
}

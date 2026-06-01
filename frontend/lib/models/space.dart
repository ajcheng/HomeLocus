class Location {
  final String id;
  final String name;
  final bool isDefault;
  final int zoneCount;

  Location({required this.id, required this.name, this.isDefault = false, this.zoneCount = 0});

  factory Location.fromJson(Map<String, dynamic> json) => Location(
        id: json['id'],
        name: json['name'],
        isDefault: json['is_default'] ?? false,
        zoneCount: json['zone_count'] ?? 0,
      );
}

class Zone {
  final String id;
  final String locationId;
  final String name;
  final String? templateType;

  Zone({required this.id, required this.locationId, required this.name, this.templateType});

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
        id: json['id'],
        locationId: json['location_id'],
        name: json['name'],
        templateType: json['template_type'],
      );
}

class Container_ {
  final String id;
  final String zoneId;
  final String name;
  final List<Slot> slots;

  Container_({required this.id, required this.zoneId, required this.name, this.slots = const []});

  factory Container_.fromJson(Map<String, dynamic> json) => Container_(
        id: json['id'],
        zoneId: json['zone_id'],
        name: json['name'],
        slots: (json['slots'] as List?)?.map((s) => Slot.fromJson(s)).toList() ?? [],
      );
}

class Slot {
  final String id;
  final String containerId;
  final String name;
  final int level;
  final int itemCount;

  Slot({required this.id, required this.containerId, required this.name, this.level = 0, this.itemCount = 0});

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
        id: json['id'],
        containerId: json['container_id'],
        name: json['name'],
        level: json['level'] ?? 0,
        itemCount: json['item_count'] ?? 0,
      );
}

class Place {
  const Place({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.id,
  });

  final String? id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  Place copyWith({String? id, String? name, String? address}) => Place(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address ?? this.address,
    latitude: latitude,
    longitude: longitude,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory Place.fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num).toDouble();
    final longitude = (json['longitude'] as num).toDouble();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Invalid saved coordinates');
    }
    return Place(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Selected location',
      address: json['address'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

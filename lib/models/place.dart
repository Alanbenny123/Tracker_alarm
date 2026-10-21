class Place {
  const Place({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.id,
    this.googleFetchedAt,
    this.sourceTracked = true,
  });

  final String? id;

  /// When coordinates came from Google Places or a resolved Maps link.
  final DateTime? googleFetchedAt;

  /// False only for records saved before coordinate provenance was recorded.
  final bool sourceTracked;
  bool expiredAt(DateTime now) =>
      googleFetchedAt != null &&
      !now.isBefore(googleFetchedAt!.add(const Duration(days: 30)));
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  Place copyWith({
    String? id,
    String? name,
    String? address,
    DateTime? googleFetchedAt,
  }) => Place(
    id: id ?? this.id,
    googleFetchedAt: googleFetchedAt ?? this.googleFetchedAt,
    sourceTracked: sourceTracked,
    name: name ?? this.name,
    address: address ?? this.address,
    latitude: latitude,
    longitude: longitude,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'googleFetchedAt': googleFetchedAt?.toIso8601String(),
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
      googleFetchedAt: json['googleFetchedAt'] == null
          ? null
          : DateTime.parse(json['googleFetchedAt'] as String),
      sourceTracked: json.containsKey('googleFetchedAt'),
      name: json['name'] as String? ?? 'Selected location',
      address: json['address'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

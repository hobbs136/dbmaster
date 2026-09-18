/// Redis Geo 成员(经度 纬度 名称)。
class GeoMember {
  final double lng;
  final double lat;
  final String name;

  const GeoMember({required this.lng, required this.lat, required this.name});
}

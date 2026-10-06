enum PlaceKind {
  town('城镇'),
  market('坊市'),
  sect('宗门驻地'),
  wild('荒野'),
  vein('灵脉'),
  ruin('遗迹'),
  secret('秘境入口'),
  tribulation('渡劫台');

  const PlaceKind(this.label);
  final String label;
}

class MapPlace {
  MapPlace(
    this.id,
    this.region,
    this.regionName,
    this.kind,
    this.x,
    this.y,
    this.terrain,
    this.aura,
    this.danger,
    List<String> resources,
  ) : resources = List.unmodifiable(resources);
  final String id, regionName, terrain;
  final int region, aura, danger;
  final double x, y;
  final PlaceKind kind;
  final List<String> resources;
  bool open(int day) => kind != PlaceKind.secret || day % 90 < 20;
  int nextOpening(int day) => open(day) ? day : day + 90 - day % 90;
  Map<String, Object?> toJson() => {
    'id': id,
    'region': region,
    'regionName': regionName,
    'kind': kind.name,
    'x': x,
    'y': y,
    'terrain': terrain,
    'aura': aura,
    'danger': danger,
    'resources': resources,
  };
  factory MapPlace.fromJson(Map<String, dynamic> j) => MapPlace(
    j['id'],
    j['region'],
    j['regionName'],
    PlaceKind.values.byName(j['kind']),
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    j['terrain'],
    j['aura'],
    j['danger'],
    List<String>.from(j['resources']),
  );
}

class MapRoad {
  const MapRoad(this.id, this.a, this.b, this.days, this.fee, this.kind);
  final String id, a, b, kind;
  final int days, fee;
  String other(String id) => id == a ? b : a;
  int travelDays(int realm) =>
      (days *
              (realm >= 3
                  ? .5
                  : realm >= 2
                  ? .7
                  : 1))
          .ceil()
          .clamp(1, 1000);
  Map<String, Object?> toJson() => {
    'id': id,
    'a': a,
    'b': b,
    'days': days,
    'fee': fee,
    'kind': kind,
  };
  factory MapRoad.fromJson(Map<String, dynamic> j) =>
      MapRoad(j['id'], j['a'], j['b'], j['days'], j['fee'], j['kind']);
}

class Journey {
  Journey(this.destination, this.roads, {this.index = 0, this.origin});
  final String destination;
  final List<String> roads;
  int index;
  String? origin;
  bool get complete => index >= roads.length;
  Map<String, Object?> toJson() => {
    'destination': destination,
    'roads': roads,
    'index': index,
    'origin': origin,
  };
  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    j['destination'],
    List<String>.from(j['roads']),
    index: j['index'],
    origin: j['origin'],
  );
}

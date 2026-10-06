import 'models.dart';

/// Only observed geography crosses the UI boundary. No raw World in widgets.
class KnownPlace {
  const KnownPlace(
    this.place,
    this.name,
    this.confirmed,
    this.time,
    this.channel,
  );
  final MapPlace place;
  final String name;
  final bool confirmed;
  final int time;
  final InformationChannel channel;
}

class MapView {
  const MapView({
    this.places = const [],
    this.roads = const [],
    this.current = '',
    this.remaining = const [],
    this.destination,
    this.paused = false,
  });
  final List<KnownPlace> places;
  final List<MapRoad> roads, remaining;
  final String current;
  final String? destination;
  final bool paused;
}

class MapRepository {
  MapRepository(this.world, {String? observer})
    : observer = observer ?? world.playerId;
  final World world;
  final String observer;
  MapView query({String search = '', PlaceKind? kind}) {
    final places = <KnownPlace>[];
    final confirmed = <String>{};
    for (final k in world.knowledge.values.where(
      (k) => k.observer == observer,
    )) {
      final p = world.mapPlaces[k.subject];
      if (p == null) continue;
      // Geography is immutable within this generation; remote NPCs/stock are not included.
      if (k.confirmed) confirmed.add(p.id);
      final name = world.entities[p.id]!.name;
      if (name.contains(search) && (kind == null || p.kind == kind)) {
        places.add(
          KnownPlace(
            k.confirmed
                ? p
                : MapPlace(
                    p.id,
                    p.region,
                    p.regionName,
                    p.kind,
                    p.x,
                    p.y,
                    '待查证',
                    0,
                    0,
                    const [],
                  ),
            name,
            k.confirmed,
            k.snapshot['geographyTime'] as int? ?? k.time,
            InformationChannel.values.byName(
              k.snapshot['geographyChannel'] as String? ?? k.channel.name,
            ),
          ),
        );
      }
    }
    final roads = world.mapRoads.values
        .where((r) => confirmed.contains(r.a) && confirmed.contains(r.b))
        .toList();
    final journey = observer == world.playerId ? world.journey : null;
    return MapView(
      places: places,
      roads: roads,
      current: world.entities[observer]!.location,
      remaining: journey == null
          ? []
          : journey.roads
                .skip(journey.index)
                .map((id) => world.mapRoads[id]!)
                .where(
                  (r) => confirmed.contains(r.a) && confirmed.contains(r.b),
                )
                .toList(),
      destination: journey != null && confirmed.contains(journey.destination)
          ? journey.destination
          : null,
      paused:
          world.encounter != null ||
          world.battleTarget != null ||
          world.tribulation != null,
    );
  }

  List<MapRoad>? route(String target) {
    if (!world.knows(observer, target)) return null;
    final actor = world.entities[observer]!;
    final view = query();
    final distance = <String, int>{actor.location: 0};
    final previous = <String, MapRoad>{};
    final pending = view.places
        .where((p) => p.confirmed)
        .map((p) => p.place.id)
        .toSet();
    while (pending.isNotEmpty) {
      final reachable = pending.where(distance.containsKey).toList();
      if (reachable.isEmpty) break;
      reachable.sort((a, b) {
        final d = distance[a]!.compareTo(distance[b]!);
        return d != 0 ? d : a.compareTo(b);
      });
      final current = reachable.first;
      pending.remove(current);
      if (current == target) break;
      for (final road in view.roads.where(
        (r) => r.a == current || r.b == current,
      )) {
        final next = road.other(current);
        if (!pending.contains(next)) continue;
        final cost = distance[current]! + road.travelDays(actor.realm);
        if (cost < (distance[next] ?? 1 << 30)) {
          distance[next] = cost;
          previous[next] = road;
        }
      }
    }
    if (!distance.containsKey(target)) return null;
    final path = <MapRoad>[];
    var current = target;
    while (current != actor.location) {
      final road = previous[current]!;
      path.add(road);
      current = road.other(current);
    }
    return path.reversed.toList();
  }
}

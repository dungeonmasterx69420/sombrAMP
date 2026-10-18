import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:finamp/hive_registrar.g.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const source = QueueItemSource.rawId(
  type: QueueItemSourceType.album,
  name: QueueItemSourceName(type: QueueItemSourceNameType.preTranslated, pretranslatedName: "Album"),
  id: "album",
);

FinampQueueItem track(String id) => FinampQueueItem(
  item: MediaItem(
    id: id,
    title: id,
    extras: {
      "itemJson": {"Id": BaseItemId(id)},
    },
  ),
  source: source,
);

FinampQueueInfo queueOf(List<String> ids) => FinampQueueInfo(
  id: "queue",
  previousTracks: [track(ids[0])],
  currentTrack: track(ids[1]),
  nextUp: [track(ids[2])],
  queue: [track(ids[3]), track(ids[4])],
  source: source,
  saveState: SavedQueueState.saving,
  sourceLibrary: null,
);

FinampStorableQueueInfo store(FinampQueueInfo info) =>
    FinampStorableQueueInfo.fromQueueInfo(info, 1000, FinampPlaybackOrder.linear, [0, 1, 2, 3, 4]);

void expectIds(FinampStorableQueueInfo stored, List<String> ids) {
  expect(stored.trackCount, 5);
  expect(stored.previousTracks, [BaseItemId(ids[0])]);
  expect(stored.currentTrack, BaseItemId(ids[1]));
  expect(stored.nextUp, [BaseItemId(ids[2])]);
  expect(stored.queue, [BaseItemId(ids[3]), BaseItemId(ids[4])]);
  expect(stored.trackSources, everyElement(source));
}

void main() {
  // Navidrome's ids, which aren't hexadecimal
  const subsonicIds = ["7yPOQvKfOul2Y3q5r4uF81", "1", "a/b c", "5MO2PXFH9w2NYRUz7aW3Bn", "tr-1"];
  const jellyfinIds = [
    "00000000000000000000000000000001",
    "0123456789abcdef0123456789abcdef",
    "fedcba9876543210fedcba9876543210",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "ffffffffffffffffffffffffffffffff",
  ];

  test("queues of Subsonic tracks are stored with their ids", () {
    final stored = store(queueOf(subsonicIds));
    expectIds(stored, subsonicIds);
    expect(stored.packedQueue, isEmpty);
  });

  test("queues of Jellyfin tracks are still packed", () {
    final stored = store(queueOf(jellyfinIds));
    expectIds(stored, jellyfinIds);
    expect(stored.packedQueue, hasLength(32));
    expect(stored.queueIds, isNull);
  });

  test("stored queues survive a restart", () async {
    final directory = await Directory.systemTemp.createTemp("finamp_queues");
    addTearDown(() => directory.delete(recursive: true));
    Hive.init(directory.path);
    Hive.registerAdapters();

    var box = await Hive.openBox<FinampStorableQueueInfo>("Queues");
    await box.put("subsonic", store(queueOf(subsonicIds)));
    await box.put("jellyfin", store(queueOf(jellyfinIds)));
    await box.close();

    box = await Hive.openBox<FinampStorableQueueInfo>("Queues");
    expectIds(box.get("subsonic")!, subsonicIds);
    expectIds(box.get("jellyfin")!, jellyfinIds);
    expect(box.get("jellyfin")!.currentTrackSeek, 1000);
    await box.close();
  });
}

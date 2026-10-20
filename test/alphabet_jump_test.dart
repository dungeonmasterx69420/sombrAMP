import 'package:finamp/components/MusicScreen/alphabet_item_list.dart';
import 'package:finamp/components/MusicScreen/music_screen_tab_view.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

void main() {
  group("indexForLetter", () {
    const ascending = ["10cc", "abba", "air", "beatles", "cars", "eagles", "zz top"];

    test("finds the first item starting with the letter", () {
      expect(indexForLetter(ascending, "A", descending: false), 1);
      expect(indexForLetter(ascending, "B", descending: false), 3);
      expect(indexForLetter(ascending, "Z", descending: false), 6);
    });

    test("compares letters regardless of case", () {
      // Sort keys are lower case, like the names in the tracks tab once normalized
      expect(indexForLetter(["abba", "beatles"], "B", descending: false), 1);
      expect(indexForLetter(["abba", "beatles"], "b", descending: false), 1);
    });

    test("goes to the next letter when none start with it", () {
      expect(indexForLetter(ascending, "D", descending: false), 5);
    });

    test("goes to the top for #", () {
      expect(indexForLetter(ascending, "#", descending: false), 0);
    });

    test("skips empty names", () {
      expect(indexForLetter(["", "abba"], "A", descending: false), 1);
    });

    test("is null when the item isn't loaded yet", () {
      expect(indexForLetter(["abba", "beatles"], "M", descending: false), isNull);
      expect(indexForLetter([], "#", descending: false), isNull);
    });

    group("descending", () {
      final descending = ascending.reversed.toList();

      test("finds the first item starting with the letter", () {
        expect(indexForLetter(descending, "Z", descending: true), 0);
        expect(indexForLetter(descending, "A", descending: true), 4);
      });

      test("goes to the next letter in sort order when none start with it", () {
        expect(indexForLetter(descending, "D", descending: true), 2);
      });

      test("goes to the numbers and punctuation at the end for #", () {
        expect(indexForLetter(descending, "#", descending: true), 6);
        expect(indexForLetter(["zz top", "abba"], "#", descending: true), isNull);
      });
    });
  });

  testWidgets("tapping a letter brings its first item to the top of the list", (tester) async {
    final names = [
      for (final letter in ["#", "A", "B", "C", "E", "M", "S", "Z"])
        for (var i = 0; i < 15; i++) "${letter == "#" ? "1" : letter.toLowerCase()} $i",
    ];
    final controller = AutoScrollController(suggestedRowHeight: 72);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AlphabetList(
              callback: (letter) => controller.scrollToIndex(
                indexForLetter(names, letter, descending: false)!,
                preferPosition: AutoScrollPosition.begin,
              ),
              sortOrder: SortOrder.ascending,
              scrollController: controller,
              inGridMode: false,
              child: ListView.builder(
                controller: controller,
                itemCount: names.length,
                itemBuilder: (context, index) => AutoScrollTag(
                  key: ValueKey(index),
                  controller: controller,
                  index: index,
                  // Rows of different heights, none of them the suggested one
                  child: SizedBox(height: index.isEven ? 56 : 90, child: Text(names[index])),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    String topItem() {
      final listTop = tester.getTopLeft(find.byType(ListView)).dy;
      return names.firstWhere((name) {
        final finder = find.text(name);
        return finder.evaluate().isNotEmpty && tester.getTopLeft(finder).dy >= listTop - 0.5;
      });
    }

    for (final (letter, expected) in [("S", "s 0"), ("C", "c 0"), ("D", "e 0"), ("Z", "z 0"), ("#", "1 0")]) {
      await tester.tap(find.text(letter));
      await tester.pumpAndSettle();
      expect(topItem(), expected, reason: "after tapping $letter");
    }
  });
}

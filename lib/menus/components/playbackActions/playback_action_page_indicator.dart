import 'package:finamp/models/finamp_models.dart';
import 'package:flutter/material.dart';

import '../../../extensions/localizations.dart';

class PlaybackActionPageIndicator extends StatelessWidget {
  const PlaybackActionPageIndicator({
    super.key,
    required this.pages,
    required this.pageController,
    this.compactLayout = false,
  });

  final Map<PlaybackActionRowPage, Widget> pages;
  final PageController pageController;
  final bool compactLayout;

  @override
  Widget build(BuildContext context) {
    // System S segmented options: ink-edged, the chosen one inverted.
    final labelStyle = TextTheme.of(context).labelMedium!;
    final textColorSelected = labelStyle.copyWith(color: Theme.of(context).colorScheme.onPrimary);
    final textColor = labelStyle.copyWith(color: Theme.of(context).colorScheme.onSurface);
    final buttonColorSelected = Theme.of(context).colorScheme.primary;
    final buttonColor = Theme.of(context).colorScheme.surfaceContainer;

    return Padding(
      padding: compactLayout ? EdgeInsets.only(top: 4.0) : EdgeInsets.only(bottom: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            pages.length,
            (index) => AnimatedBuilder(
              animation: pageController,
              builder: (context, child) {
                return GestureDetector(
                  onTap: () {
                    pageController.animateToPage(
                      index,
                      duration: Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: (pageController.page ?? pageController.initialPage).round() == index
                          ? buttonColorSelected
                          : buttonColor,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Text(
                      pages.keys.elementAt(index).toLocalisedString(context.l10n),
                      style: (pageController.page ?? pageController.initialPage).round() == index
                          ? textColorSelected
                          : textColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

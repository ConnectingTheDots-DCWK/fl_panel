import 'package:flutter/material.dart';

/// How the tabs of a group are drawn.
///
/// - `attached`: rectangular chips flush against each other and the content,
///   a hairline between neighbours, an accent line on top of the active one.
///   VS Code.
/// - `blended`: the active chip is cut out of a darker strip floor with
///   curved shoulders and runs into the content with no line between; the
///   inactive ones sit on the floor with short separators. Chrome.
/// - `floating`: pills inset from the strip, the active one filled, a
///   hairline under the whole strip. Zed, Arc, the newer JetBrains UI.
enum PanelTabStyle { attached, blended, floating }

/// The geometry of one [PanelTabStyle]. Each style has defaults, see
/// [PanelTabStyleSpec.of]; a theme may override them for the style it uses.
final class PanelTabStyleSpec {
  const PanelTabStyleSpec({
    this.radius = 0,
    this.shoulder = 0,
    this.gap = 0,
    this.inset = EdgeInsets.zero,
    this.indicator = 0,
  });

  /// Corner radius of the chip's top corners (all four for `floating`).
  final double radius;

  /// Width of the curve where a `blended` chip meets the strip floor, on each
  /// side. Also how much of the chip's box the curve consumes, so the text
  /// has that much less room.
  final double shoulder;

  /// Space between neighbouring chips.
  final double gap;

  /// Padding between the strip's edges and the chips.
  final EdgeInsets inset;

  /// Thickness of the active-tab accent line for `attached`.
  final double indicator;

  static const attached = PanelTabStyleSpec(indicator: 2);
  static const blended = PanelTabStyleSpec(
    radius: 8,
    shoulder: 8,
    inset: EdgeInsets.only(top: 6),
  );
  static const floating = PanelTabStyleSpec(
    radius: 6,
    gap: 4,
    inset: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  );

  static PanelTabStyleSpec of(PanelTabStyle style) => switch (style) {
    PanelTabStyle.attached => attached,
    PanelTabStyle.blended => blended,
    PanelTabStyle.floating => floating,
  };
}

/// The look of the chrome: strips, headers, dividers, the drop preview.
///
/// Every colour is optional and falls back to the ambient `ColorScheme` in
/// [resolve], so a host with a theme gets chrome that matches it for free and
/// a host with opinions overrides one field at a time. Divider thickness is
/// not here: it is geometry the solver needs, so it lives on `PanelSolver`.
final class PanelTheme {
  const PanelTheme({
    this.tabStyle = PanelTabStyle.attached,
    this.tabStyleSpec,
    this.stripHeight = 34,
    this.headerHeight = 28,
    this.tabMinWidth = 96,
    this.tabMaxWidth = 200,
    this.stripColor,
    this.tabColor,
    this.activeTabColor,
    this.hoverTabColor,
    this.headerColor,
    this.dividerColor,
    this.dividerHoverColor,
    this.indicatorColor,
    this.unfocusedIndicatorColor,
    this.dropPreviewColor,
    this.dropPreviewBorderColor,
    this.textStyle,
    this.activeTextStyle,
    this.iconColor,
  });

  final PanelTabStyle tabStyle;

  /// Geometry for [tabStyle]; null takes the style's defaults.
  final PanelTabStyleSpec? tabStyleSpec;

  /// Height of a tab group's strip.
  final double stripHeight;

  /// Height of a single panel's header.
  final double headerHeight;

  /// Chips share the strip equally, never wider than [tabMaxWidth]; when the
  /// strip is too narrow for every chip at [tabMinWidth] they stop shrinking
  /// and the strip scrolls instead. Set the two equal for chips that never
  /// shrink.
  final double tabMinWidth;
  final double tabMaxWidth;

  final Color? stripColor;
  final Color? tabColor;
  final Color? activeTabColor;
  final Color? hoverTabColor;
  final Color? headerColor;
  final Color? dividerColor;
  final Color? dividerHoverColor;

  /// The accent on the active tab of the *focused* group; the strip of the
  /// group the user last worked in is the one that shows it in full.
  final Color? indicatorColor;
  final Color? unfocusedIndicatorColor;
  final Color? dropPreviewColor;
  final Color? dropPreviewBorderColor;
  final TextStyle? textStyle;
  final TextStyle? activeTextStyle;
  final Color? iconColor;

  PanelTabStyleSpec get spec => tabStyleSpec ?? PanelTabStyleSpec.of(tabStyle);

  /// This theme with [style] and, unless overridden, that style's geometry.
  PanelTheme withTabStyle(PanelTabStyle style) => style == tabStyle
      ? this
      : copyWith(tabStyle: style, clearTabStyleSpec: true);

  /// This theme with whatever is named replaced.
  ///
  /// A null argument means *keep*, so [clearTabStyleSpec] is how the spec is
  /// taken away to fall back to the style's own geometry.
  PanelTheme copyWith({
    PanelTabStyle? tabStyle,
    PanelTabStyleSpec? tabStyleSpec,
    bool clearTabStyleSpec = false,
    double? stripHeight,
    double? headerHeight,
    double? tabMinWidth,
    double? tabMaxWidth,
    Color? stripColor,
    Color? tabColor,
    Color? activeTabColor,
    Color? hoverTabColor,
    Color? headerColor,
    Color? dividerColor,
    Color? dividerHoverColor,
    Color? indicatorColor,
    Color? unfocusedIndicatorColor,
    Color? dropPreviewColor,
    Color? dropPreviewBorderColor,
    TextStyle? textStyle,
    TextStyle? activeTextStyle,
    Color? iconColor,
  }) {
    assert(
      !clearTabStyleSpec || tabStyleSpec == null,
      'pass a tabStyleSpec or clearTabStyleSpec, not both',
    );
    return PanelTheme(
      tabStyle: tabStyle ?? this.tabStyle,
      tabStyleSpec: clearTabStyleSpec
          ? null
          : tabStyleSpec ?? this.tabStyleSpec,
      stripHeight: stripHeight ?? this.stripHeight,
      headerHeight: headerHeight ?? this.headerHeight,
      tabMinWidth: tabMinWidth ?? this.tabMinWidth,
      tabMaxWidth: tabMaxWidth ?? this.tabMaxWidth,
      stripColor: stripColor ?? this.stripColor,
      tabColor: tabColor ?? this.tabColor,
      activeTabColor: activeTabColor ?? this.activeTabColor,
      hoverTabColor: hoverTabColor ?? this.hoverTabColor,
      headerColor: headerColor ?? this.headerColor,
      dividerColor: dividerColor ?? this.dividerColor,
      dividerHoverColor: dividerHoverColor ?? this.dividerHoverColor,
      indicatorColor: indicatorColor ?? this.indicatorColor,
      unfocusedIndicatorColor:
          unfocusedIndicatorColor ?? this.unfocusedIndicatorColor,
      dropPreviewColor: dropPreviewColor ?? this.dropPreviewColor,
      dropPreviewBorderColor:
          dropPreviewBorderColor ?? this.dropPreviewBorderColor,
      textStyle: textStyle ?? this.textStyle,
      activeTextStyle: activeTextStyle ?? this.activeTextStyle,
      iconColor: iconColor ?? this.iconColor,
    );
  }

  /// This theme with every null filled from [theme].
  PanelTheme resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final text =
        textStyle ?? theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    // The blended floor sits a step darker than the content so the active tab
    // reads as cut out of it; the other two styles keep the strip close to
    // the content and let the chips carry the contrast.
    final floor = tabStyle == PanelTabStyle.blended
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLow;
    return PanelTheme(
      tabStyle: tabStyle,
      tabStyleSpec: spec,
      stripHeight: stripHeight,
      headerHeight: headerHeight,
      tabMinWidth: tabMinWidth,
      tabMaxWidth: tabMaxWidth,
      stripColor: stripColor ?? floor,
      tabColor: tabColor ?? Colors.transparent,
      activeTabColor:
          activeTabColor ??
          (tabStyle == PanelTabStyle.floating
              ? scheme.surfaceContainerHighest
              : scheme.surface),
      hoverTabColor: hoverTabColor ?? scheme.onSurface.withValues(alpha: 0.06),
      headerColor: headerColor ?? scheme.surfaceContainerLow,
      dividerColor: dividerColor ?? scheme.outlineVariant,
      dividerHoverColor: dividerHoverColor ?? scheme.primary,
      indicatorColor: indicatorColor ?? scheme.primary,
      unfocusedIndicatorColor: unfocusedIndicatorColor ?? scheme.outlineVariant,
      dropPreviewColor:
          dropPreviewColor ?? scheme.primary.withValues(alpha: 0.18),
      dropPreviewBorderColor: dropPreviewBorderColor ?? scheme.primary,
      textStyle: text.copyWith(color: text.color ?? scheme.onSurfaceVariant),
      activeTextStyle:
          activeTextStyle ??
          text.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
      iconColor: iconColor ?? scheme.onSurfaceVariant,
    );
  }
}

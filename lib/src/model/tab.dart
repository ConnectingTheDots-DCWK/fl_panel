/// The two shapes a piece of content can be shown in.
///
/// `single` is a panel of its own: a header or nothing above the content, no
/// strip. `tabbed` is one tab among others in a group, which always draws a
/// strip — even when it holds one tab. Which forms a content may take is the
/// first of the two affinity levels, and it is answered per tab.
enum SurfaceForm { single, tabbed }

/// One piece of content in the layout.
///
/// A tab holds an identity, never a widget. `contentId` names what the host
/// should build here, `metadata` carries whatever the host wants to know about
/// it — a path, a kind, a title — as JSON-compatible values. Three things rest
/// on that: the tree serialises without asking anybody, a tab moving between
/// windows (separate engines under multi-window, nothing can carry a widget
/// across) is a tree edit and a rebuild from identity, and the host keeps
/// ownership of what a tab *is*.
final class PanelTab {
  PanelTab({
    required this.id,
    required this.contentId,
    Map<String, Object?> metadata = const {},
    Set<SurfaceForm> allowedForms = const {
      SurfaceForm.single,
      SurfaceForm.tabbed,
    },
    this.keepAlive = true,
    this.closable = true,
    this.minWidth = 0,
    this.minHeight = 0,
  }) : assert(
         allowedForms.isNotEmpty,
         'a tab must be allowed at least one form',
       ),
       metadata = Map.unmodifiable(metadata),
       allowedForms = Set.unmodifiable(allowedForms);

  final String id;
  final String contentId;
  final Map<String, Object?> metadata;

  /// The surface forms this content may take. A tab dragged out of a strip
  /// becomes a single panel only if `single` is here; a single panel dropped
  /// onto a group joins it only if `tabbed` is.
  final Set<SurfaceForm> allowedForms;

  /// Whether the content is kept built while another tab in its group is
  /// active. On by default so a text field keeps its scroll and selection;
  /// off for content too heavy to hold offstage.
  final bool keepAlive;

  /// Whether the user may close this tab. Off for content the application
  /// always shows — a file tree, a console — the way an editor's tool
  /// windows hide rather than close: the chrome draws no close glyph and
  /// `PanelController.close` refuses without asking the guard. The tab can
  /// still be moved, and the application can still remove it through an
  /// edit of the tree.
  final bool closable;

  /// The smallest size the content is useful at. The leaf holding this tab is
  /// never laid out smaller unless the whole window is over-constrained.
  final double minWidth;
  final double minHeight;

  bool allows(SurfaceForm form) => allowedForms.contains(form);

  /// The [metadata] value under [key] as a [T], or null when there is none or
  /// it is something else.
  ///
  /// Metadata comes back from a file, so a value of the wrong type is a stale
  /// or hand-edited layout rather than a programming error, and it reads as
  /// missing instead of throwing. One widening is made: an `int` is accepted
  /// as a `double`, because a number that was written as `1.0` comes back as
  /// `1` from anything that is not the Dart VM — a web build, a script, a
  /// person with a text editor.
  T? metadataValue<T extends Object>(String key) {
    final value = metadata[key];
    if (value is T) return value;
    if (value is int && 0.0 is T) return value.toDouble() as T;
    return null;
  }

  PanelTab copyWith({
    String? contentId,
    Map<String, Object?>? metadata,
    Set<SurfaceForm>? allowedForms,
    bool? keepAlive,
    bool? closable,
    double? minWidth,
    double? minHeight,
  }) => PanelTab(
    id: id,
    contentId: contentId ?? this.contentId,
    metadata: metadata ?? this.metadata,
    allowedForms: allowedForms ?? this.allowedForms,
    keepAlive: keepAlive ?? this.keepAlive,
    closable: closable ?? this.closable,
    minWidth: minWidth ?? this.minWidth,
    minHeight: minHeight ?? this.minHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is PanelTab &&
      other.id == id &&
      other.contentId == contentId &&
      other.keepAlive == keepAlive &&
      other.closable == closable &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      _sameSet(other.allowedForms, allowedForms) &&
      _sameMap(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(id, contentId);

  @override
  String toString() => 'PanelTab($id → $contentId)';
}

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);

bool _sameMap(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (!_sameValue(entry.value, b[entry.key])) return false;
  }
  return true;
}

// Metadata is JSON-shaped, so equality has to walk it: two tabs restored from
// the same file must compare equal even though their maps are distinct objects.
bool _sameValue(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return _sameMap(a, b);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

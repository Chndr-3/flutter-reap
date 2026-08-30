/// The outcome of asking the user what to keep.
sealed class Selection {
  const Selection();
}

/// Keep these one-based indexes; delete everything else that was listed.
class KeepIndexes extends Selection {
  /// One-based positions in the listing that must not be deleted.
  final Set<int> indexes;

  /// Creates a selection that keeps exactly these one-based positions.
  const KeepIndexes(this.indexes);
}

/// Delete nothing at all.
class CancelSelection extends Selection {
  /// Creates a cancellation that prevents any deletion.
  const CancelSelection();
}

/// Interpret the answer to "keep which?" against a listing of [count] entries.
///
/// An empty answer keeps nothing, which deletes everything listed. `k` keeps
/// everything, which cancels. Anything unparseable or out of range cancels
/// rather than guessing: on a tool that deletes directories, a misread answer
/// must fail towards doing nothing.
///
/// Supports:
/// - Empty or whitespace-only input: keeps nothing, deletes all
/// - `k` or `K`: cancels, deletes nothing
/// - Single numbers: `3` keeps position 3
/// - Comma-separated: `1,3` keeps positions 1 and 3
/// - Inclusive ranges: `2-4` keeps positions 2, 3, and 4
/// - Mixed: `1, 3-5` keeps positions 1, 3, 4, and 5
/// - Whitespace is tolerated around tokens and within ranges: ` 2 - 4 `
/// - Duplicates are kept once: `2,2` keeps position 2
///
/// Returns [CancelSelection] if input is unparseable, out of range, or has
/// a backwards range.
Selection parseSelection(String input, int count) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const KeepIndexes({});
  if (trimmed.toLowerCase() == 'k') return const CancelSelection();

  final keep = <int>{};
  for (final part in trimmed.split(',')) {
    final token = part.trim();
    if (token.isEmpty) return const CancelSelection();

    if (token.contains('-')) {
      final bounds = token.split('-');
      if (bounds.length != 2) return const CancelSelection();
      final start = int.tryParse(bounds[0].trim());
      final end = int.tryParse(bounds[1].trim());
      if (start == null || end == null) return const CancelSelection();
      if (start > end) return const CancelSelection();
      if (start < 1 || end > count) return const CancelSelection();
      for (var i = start; i <= end; i++) {
        keep.add(i);
      }
    } else {
      final value = int.tryParse(token);
      if (value == null) return const CancelSelection();
      if (value < 1 || value > count) return const CancelSelection();
      keep.add(value);
    }
  }
  return KeepIndexes(keep);
}

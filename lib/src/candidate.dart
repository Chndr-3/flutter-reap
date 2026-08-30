/// What kind of thing a [Candidate] is, which decides how it may be deleted.
enum CandidateKind {
  /// A generated directory inside a Flutter project, such as `build/`.
  projectArtifact,

  /// A machine-wide cache such as Xcode's DerivedData.
  sharedCache,

  /// An installed fvm SDK version that no project references.
  fvmSdk,
}

/// One directory that could be deleted, with everything needed to display it.
class Candidate {
  /// Absolute path of the directory.
  final String path;

  /// Total size on disk, in bytes.
  final int bytes;

  /// Which category this belongs to.
  final CandidateKind kind;

  /// Human-readable name shown in listings.
  final String label;

  /// Days since a human last touched the owning project, or null when the
  /// candidate is not owned by a project.
  final int? ageDays;

  /// Whether the owning project has uncommitted changes.
  final bool dirty;

  /// Creates a candidate for deletion.
  const Candidate({
    required this.path,
    required this.bytes,
    required this.kind,
    required this.label,
    this.ageDays,
    this.dirty = false,
  });

  /// Size rounded down to whole megabytes.
  int get megabytes => bytes ~/ (1024 * 1024);
}

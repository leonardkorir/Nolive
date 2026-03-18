class LivePlayQuality {
  const LivePlayQuality({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.sortOrder = 0,
    this.metadata,
  });

  final String id;
  final String label;
  final bool isDefault;
  final int sortOrder;
  final Map<String, Object?>? metadata;
}

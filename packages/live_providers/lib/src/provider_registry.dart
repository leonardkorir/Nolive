import 'package:live_core/live_core.dart';

/// A borrowed handle to a cached [LiveProvider].
///
/// The underlying instance is kept alive until every outstanding lease is
/// released, so a request in flight is never cut short by a concurrent
/// [ProviderRegistry.invalidate] or [ProviderRegistry.clearCache].
class ProviderLease {
  ProviderLease._(this._entry);

  final _CachedProvider _entry;
  bool _released = false;

  LiveProvider get provider => _entry.provider;

  /// Returns the instance to the registry. Safe to call more than once.
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _entry.release();
  }
}

class _CachedProvider {
  _CachedProvider(this.provider);

  final LiveProvider provider;
  int _leases = 0;
  bool _retired = false;
  bool _disposed = false;

  ProviderLease acquire() {
    _leases += 1;
    return ProviderLease._(this);
  }

  void release() {
    if (_leases > 0) {
      _leases -= 1;
    }
    _disposeIfIdle();
  }

  /// Marks the instance as evicted from the cache.
  ///
  /// Disposal is deferred until the last outstanding lease is released, so
  /// eviction (a credential change, a retry asking for a fresh instance) never
  /// closes an HTTP client that a concurrent caller is still reading from.
  void retire() {
    _retired = true;
    _disposeIfIdle();
  }

  void _disposeIfIdle() {
    if (!_retired || _leases > 0 || _disposed) {
      return;
    }
    _disposed = true;
    provider.dispose();
  }
}

class ProviderRegistry {
  final Map<String, ProviderRegistration> _registrations = {};
  final Map<String, _CachedProvider> _instances = {};

  Iterable<ProviderRegistration> get registrations => _registrations.values;

  Iterable<ProviderDescriptor> get descriptors {
    return _registrations.values.map((item) => item.descriptor);
  }

  void register(ProviderRegistration registration) {
    final providerId = registration.descriptor.id.value;
    _instances.remove(providerId)?.retire();
    _registrations[providerId] = registration;
  }

  ProviderRegistration? findRegistration(ProviderId providerId) {
    return _registrations[providerId.value];
  }

  ProviderDescriptor? findDescriptor(ProviderId providerId) {
    return findRegistration(providerId)?.descriptor;
  }

  ProviderDescriptor? findDescriptorById(String providerId) {
    return _registrations[providerId]?.descriptor;
  }

  bool hasImplementation(ProviderId providerId) {
    return findRegistration(providerId)?.hasImplementation ?? false;
  }

  /// Returns the cached instance without taking a lease.
  ///
  /// Only safe for synchronous inspection (capabilities, descriptor). Anything
  /// that awaits must go through [use] or [lease]; otherwise a concurrent
  /// [invalidate] can dispose the instance mid-request.
  LiveProvider create(ProviderId providerId) => _entry(providerId).provider;

  /// Borrows the cached instance until the returned lease is released.
  ///
  /// Prefer [use] unless the borrowed instance must outlive a single call (an
  /// open danmaku session, for example).
  ProviderLease lease(ProviderId providerId) => _entry(providerId).acquire();

  /// Runs [action] against the cached instance, holding a lease for its whole
  /// duration.
  ///
  /// Do not let the provider escape [action]; use [lease] for that instead.
  Future<T> use<T>(
    ProviderId providerId,
    Future<T> Function(LiveProvider provider) action,
  ) async {
    final borrowed = lease(providerId);
    try {
      return await action(borrowed.provider);
    } finally {
      borrowed.release();
    }
  }

  _CachedProvider _entry(ProviderId providerId) {
    final cached = _instances[providerId.value];
    if (cached != null) {
      return cached;
    }
    final registration = findRegistration(providerId);
    if (registration == null) {
      throw ProviderNotImplementedException.migration(
        providerId: providerId,
        feature: 'provider registration',
      );
    }
    final entry = _CachedProvider(registration.create());
    _instances[providerId.value] = entry;
    return entry;
  }

  /// Evicts the cached instance so the next caller builds a fresh one.
  ///
  /// Disposal waits for outstanding leases.
  void invalidate(ProviderId providerId) {
    _instances.remove(providerId.value)?.retire();
  }

  /// Evicts every cached instance. Disposal waits for outstanding leases.
  void clearCache() {
    final entries = _instances.values.toList(growable: false);
    _instances.clear();
    for (final entry in entries) {
      entry.retire();
    }
  }
}

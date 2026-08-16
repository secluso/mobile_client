/// Which delivery service the stored credentials correspond to.
enum ServerBackend {
  selfHosted('self_hosted'),
  enterprise('enterprise');

  const ServerBackend(this.wireName);

  final String wireName;

  bool get isEnterprise => this == ServerBackend.enterprise;

  static ServerBackend parse(String? value) {
    final normalized = value?.trim().toLowerCase();

    for (final backend in ServerBackend.values) {
      if (backend.wireName == normalized) {
        return backend;
      }
    }

    if (normalized == 'selfhosted') {
      return ServerBackend.selfHosted;
    }

    return ServerBackend.selfHosted;
  }
}

import 'package:secluso_flutter/utilities/rust_api.dart' as rust_api;
import 'package:secluso_flutter/utilities/server_backend.dart';

/// Object names for the enterprise delivery service.
///
/// Talked about this more in the Rust code.
class ObjectName {
  const ObjectName._();

  /// The name a motion video is stored under.
  static Future<String> forEpoch({
    required String cameraName,
    required String groupName,
    required int epoch,
  }) => _derive(
    cameraName: cameraName,
    clientTag: 'motion',
    groupName: groupName,
    epoch: epoch,
  );

  static Future<String> forThumbnail({
    required String cameraName,
    required String groupName,
    required int epoch,
  }) => _derive(
    cameraName: cameraName,
    clientTag: 'thumbnail',
    groupName: groupName,
    epoch: epoch,
    kind: 'thumbnail',
  );

  /// Whether object naming is needed for this backend.
  static bool isRequiredFor(ServerBackend backend) => backend.isEnterprise;

  static Future<String> _derive({
    required String cameraName,
    required String clientTag,
    required String groupName,
    required int epoch,
    String kind = '',
  }) async {
    final name = await rust_api.objectNameFor(
      clientTag: clientTag,
      cameraName: cameraName,
      groupName: groupName,
      epoch: epoch,
      kind: kind,
    );

    if (name.startsWith('Error')) {
      throw Exception('Could not derive the object name for $groupName: $name');
    }

    return name;
  }
}

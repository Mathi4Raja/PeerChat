enum RuntimeProfile {
  normalDirect,
  normalMesh,
  emergencyBattery,
}

extension RuntimeProfileX on RuntimeProfile {
  String get storageValue {
    switch (this) {
      case RuntimeProfile.normalDirect:
        return 'normal_direct';
      case RuntimeProfile.normalMesh:
        return 'normal_mesh';
      case RuntimeProfile.emergencyBattery:
        return 'emergency_battery';
    }
  }

  String get shortLabel {
    switch (this) {
      case RuntimeProfile.normalDirect:
        return 'Direct';
      case RuntimeProfile.normalMesh:
        return 'Mesh';
      case RuntimeProfile.emergencyBattery:
        return 'Battery';
    }
  }

  String get description {
    switch (this) {
      case RuntimeProfile.normalDirect:
        return 'Direct chats prioritized. Mesh stays passive.';
      case RuntimeProfile.normalMesh:
        return 'Mesh-first operation. Direct/file features are disabled.';
      case RuntimeProfile.emergencyBattery:
        return 'Battery saver profile with slower discovery and mesh-first traffic.';
    }
  }
}

RuntimeProfile runtimeProfileFromStorage(String? value) {
  switch (value) {
    case 'normal_mesh':
      return RuntimeProfile.normalMesh;
    case 'emergency_battery':
      return RuntimeProfile.emergencyBattery;
    case 'normal_direct':
    default:
      return RuntimeProfile.normalDirect;
  }
}

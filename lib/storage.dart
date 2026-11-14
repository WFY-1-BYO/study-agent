/// F3 · 本地存储与保存。
///
/// 存储后端可注入（内存 / 文件 / 浏览器 localStorage 各自实现）。
/// 本地保存的内容就是一份完整的 .studypack 开放格式 —— 「存下的即能带走的」。
/// 主动（自动快照）+ 手动保存两种触发；保存失败一律向上抛出，不静默吞错。
library study_agent.storage;

import 'dart:convert';

import 'core.dart';
import 'models.dart';
import 'studypack.dart';

abstract class StorageBackend {
  void write(String key, String value);
  String? read(String key);
}

/// 纯内存后端（测试与开发验证用；真机可换成文件 / SharedPreferences 实现）。
class MemoryStorage implements StorageBackend {
  final Map<String, String> _data = <String, String>{};

  @override
  void write(String key, String value) => _data[key] = value;

  @override
  String? read(String key) => _data[key];

  Map<String, String> get raw => Map<String, String>.unmodifiable(_data);
}

class LocalRepository {
  static const String stateKey = 'studypack.json';

  final StorageBackend backend;
  final int snapshotEvery;

  int _changes = 0;
  int snapshotCount = 0;
  int manualSaveCount = 0;

  LocalRepository(this.backend, {this.snapshotEvery = 3}) {
    if (snapshotEvery <= 0) {
      throw ValidationError('snapshotEvery 必须为正整数');
    }
  }

  /// 手动保存：立即生效，并清零变更计数。
  void saveNow(DataPackage pack) {
    _write(pack);
    manualSaveCount++;
    _changes = 0;
  }

  /// 主动保存：累计变更达到阈值后自动快照。
  void recordChange(DataPackage pack) {
    _changes++;
    if (_changes >= snapshotEvery) {
      _write(pack);
      snapshotCount++;
      _changes = 0;
    }
  }

  int get pendingChanges => _changes;

  /// 恢复：走与导入完全相同的校验链路，本地数据损坏会被发现而非静默读到脏数据。
  DataPackage? load() {
    final s = backend.read(stateKey);
    if (s == null) return null;
    final files = (jsonDecode(s) as Map)
        .map((k, v) => MapEntry(k as String, v as String));
    return StudyPack.importPack(files);
  }

  /// 直接暴露开放格式文件映射（其它程序 / 别的设备可直接读）。
  Map<String, String>? readRawFiles() {
    final s = backend.read(stateKey);
    if (s == null) return null;
    return (jsonDecode(s) as Map)
        .map((k, v) => MapEntry(k as String, v as String));
  }

  void _write(DataPackage pack) {
    final files = StudyPack.exportPack(pack, device: 'local');
    backend.write(stateKey, jsonEncode(files));
  }
}

/// F2 · .studypack 全量导入导出（PRD §6 数据契约）。
///
/// 纯开放格式、不加密；凭证与第三方版权内容不进包；
/// manifest 带 schemaVersion 与 checksum，可自描述可校验。
/// 导出结果为「相对路径 → 文本内容」的扁平映射，便于打包 / 浏览器下载 / 直接读取。
library study_agent.studypack;

import 'dart:convert';

import 'core.dart';
import 'models.dart';

class StudyPack {
  static const int schemaVersion = 1;
  static const String manifestFile = 'manifest.json';
  static const String formatId = 'studypack-open-v1';

  /// 凭证类字段：出现即拒绝进包（api_key 不进 .studypack 是硬约束）。
  static const sensitiveKeys = [
    'api_key', 'apikey', 'token', 'secret', 'password',
    'access_token', 'authorization', 'private_key'
  ];

  /// 第三方版权 / 二进制内容：只存引用与元数据，不存正文。
  static const forbiddenKeys = [
    'binary', 'embeddedcontent', 'videobinary', 'pdfbinary', 'videodata'
  ];

  static void _assertClean(Object? value, String where) {
    if (value is Map) {
      for (final e in value.entries) {
        final k = e.key.toString().toLowerCase();
        if (sensitiveKeys.contains(k)) {
          throw ValidationError('$where 含凭证字段 "${e.key}"，禁止进包');
        }
        if (forbiddenKeys.contains(k)) {
          throw ValidationError(
              '$where 含第三方版权/二进制内容 "${e.key}"，禁止进包（只存引用）');
        }
        _assertClean(e.value, '$where.${e.key}');
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _assertClean(value[i], '$where[$i]');
      }
    } else if (value is String && value.trim().startsWith('sk-')) {
      throw ValidationError('$where 含疑似 API key 明文（sk- 开头），禁止进包');
    }
  }

  /// checksum 覆盖除 manifest 外的全部文件（含 assets），按文件名排序保证跨设备一致。
  static String computeChecksum(Map<String, String> files) {
    final keys = files.keys.where((k) => k != manifestFile).toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      sb.write(k);
      sb.write('\n');
      sb.write(files[k]);
      sb.write('\n');
    }
    return checksumHex(sb.toString());
  }

  /// 导出：始终输出完整 13 类实体文件（缺失补空数组），保证「固定格式」。
  static Map<String, String> exportPack(
    DataPackage pack, {
    String device = 'unknown',
    String? exportedAt,
    Map<String, String> assets = const <String, String>{},
  }) {
    _assertClean(pack.entities, 'DataPackage.entities');
    _assertClean(pack.manifest, 'DataPackage.manifest');

    final files = <String, String>{};
    for (final name in DataPackage.entityFiles) {
      final list = pack.entities[name] ?? <Map<String, dynamic>>[];
      files[name] = jsonEncode(list);
    }
    for (final e in assets.entries) {
      files[e.key] = e.value;
    }

    final now = DateTime.now().toUtc();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';

    final manifest = <String, dynamic>{
      'packageName': 'studypack-$stamp',
      'format': formatId,
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt ?? now.toIso8601String(),
      'device': device,
      'encrypted': false,
      'entityFiles': DataPackage.entityFiles,
      'assetFiles': assets.keys.toList()..sort(),
      'fileCount': files.length + 1,
      'checksum': computeChecksum(files),
    };
    files[manifestFile] = jsonEncode(manifest);
    return files;
  }

  /// 导入：校验 manifest、版本、checksum、凭证与版权内容；任何异常都拒绝。
  static DataPackage importPack(Map<String, String> files) {
    if (!files.containsKey(manifestFile)) {
      throw ValidationError('缺少 manifest.json，不是合法的 .studypack');
    }
    final decodedManifest = jsonDecode(files[manifestFile]!);
    if (decodedManifest is! Map) {
      throw ValidationError('manifest.json 应为对象');
    }
    final manifest = Map<String, dynamic>.from(decodedManifest);
    requireFields(
        manifest, ['schemaVersion', 'checksum', 'entityFiles'], 'manifest');

    final v = manifest['schemaVersion'];
    if (v is! int) throw ValidationError('manifest.schemaVersion 应为整数');
    if (v > schemaVersion) {
      throw ValidationError(
          '不支持的 schemaVersion=$v（当前支持 <= $schemaVersion）');
    }
    if (manifest['format'] != null && manifest['format'] != formatId) {
      throw ValidationError('未知格式: ${manifest['format']}');
    }

    final expected = manifest['checksum'].toString();
    final actual = computeChecksum(files);
    if (expected != actual) {
      throw ValidationError('checksum 不一致（$expected != $actual），包可能损坏或被篡改');
    }

    final entities = <String, List<Map<String, dynamic>>>{};
    for (final name in DataPackage.entityFiles) {
      if (!files.containsKey(name)) continue; // 旧版本允许缺文件
      final decoded = jsonDecode(files[name]!);
      if (decoded is! List) throw ValidationError('$name 应为数组');
      _assertClean(decoded, name);
      entities[name] = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return DataPackage(manifest: manifest, entities: entities);
  }

  /// 导入后是否发生了版本迁移（供上层标注，不改变数据）。
  static bool isMigrated(DataPackage pack) {
    final v = pack.manifest['schemaVersion'];
    return v is int && v < schemaVersion;
  }
}

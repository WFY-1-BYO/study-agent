/// 领域内核公共工具。
///
/// 约束：只依赖 dart:core / dart:convert，零第三方包，兼容 Dart 2.17。
/// 这些工具被 F1–F13 全部功能复用，是「业务规则唯一真源」的地基。
library study_agent.core;

import 'dart:convert';

/// 校验失败。任何「缺字段 / 非法值 / 违反硬约束」都必须抛它，不得静默降级。
class ValidationError implements Exception {
  final String message;
  const ValidationError(this.message);

  @override
  String toString() => 'ValidationError: $message';
}

/// 稳定 ID（可预测，便于测试与跨设备对账）。
String makeId(String prefix, int seq) =>
    '$prefix-${seq.toString().padLeft(4, '0')}';

/// 贯穿 资源标签 → 错因归因 → 笔记关联 → 复习调度 的唯一坐标。
String buildAnchorId(
        String knowledgeNodeId, String sessionId, String weakPointId) =>
    '$knowledgeNodeId::$sessionId::$weakPointId';

/// "HH:MM" → 当日零点起分钟数。非法输入抛 [ValidationError]。
int parseHm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) throw ValidationError('非法时间格式: $s');
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) throw ValidationError('时间越界: $s');
  return h * 60 + mi;
}

/// 分钟数 → "HH:MM"。
String formatHm(int minutes) {
  if (minutes < 0 || minutes >= 1440) {
    throw ValidationError('分钟数越界: $minutes');
  }
  final h = minutes ~/ 60;
  final mi = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
}

/// 半开区间 [a1,a2) 与 [b1,b2) 是否重叠。
bool intervalsOverlap(int a1, int a2, int b1, int b2) => a1 < b2 && b1 < a2;

/// 递归按 key 排序的 JSON 序列化 —— 保证同一份数据在任何设备上 checksum 一致。
String stableStringify(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final buf = StringBuffer('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buf.write(',');
      buf.write(jsonEncode(keys[i]));
      buf.write(':');
      buf.write(stableStringify(value[keys[i]]));
    }
    buf.write('}');
    return buf.toString();
  }
  if (value is List) {
    return '[${value.map(stableStringify).join(',')}]';
  }
  return jsonEncode(value);
}

/// FNV-1a 32bit，用于 manifest.checksum（不追求密码学强度，只做完整性校验）。
int checksum32(String text) {
  const int offset = 0x811c9dc5;
  const int prime = 0x01000193;
  var h = offset;
  for (final b in utf8.encode(text)) {
    h = ((h ^ b) * prime) & 0xffffffff;
  }
  return h;
}

String checksumHex(String text) =>
    checksum32(text).toRadixString(16).padLeft(8, '0');

/// 深度 JSON 比较（测试用）。
bool jsonEquals(Object? a, Object? b) => stableStringify(a) == stableStringify(b);

/// 必填字段校验助手。
void requireFields(Map<String, dynamic> json, List<String> fields, String where) {
  for (final f in fields) {
    if (!json.containsKey(f) || json[f] == null) {
      throw ValidationError('$where 缺少必填字段 $f');
    }
  }
}

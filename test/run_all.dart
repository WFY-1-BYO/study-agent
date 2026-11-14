/// 全量回归：自动发现 test/tF*.dart，逐个真实执行并汇总。
///
/// 用法：dart test/run_all.dart
/// 新增功能无需改本文件 —— 只要放一个 tFxx_*.dart，就会被自动纳入回归。
/// 任一测试文件 FAIL / 非零退出，整体即失败（不降低要求）。
library study_agent.run_all;

import 'dart:io';

void main() {
  final dart = Platform.resolvedExecutable;
  final dir = Directory('test');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) {
        final n = f.uri.pathSegments.last;
        return n.endsWith('.dart') &&
            RegExp(r'^tF\d+_').hasMatch(n) &&
            n != 'framework.dart';
      })
      .toList()
    ..sort((a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));

  if (files.isEmpty) {
    stderr.writeln('未发现任何 tF*.dart 测试文件，回归失败');
    exit(1);
  }

  stdout.writeln('===== 全量回归：发现 ${files.length} 个功能测试 =====');
  var totalPass = 0;
  var totalFail = 0;
  final failedFiles = <String>[];

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final r = Process.runSync(dart, [f.path], workingDirectory: Directory.current.path);
    final out = '${r.stdout}${r.stderr}';
    final m = RegExp(r'TOTAL pass=(\d+) fail=(\d+)').firstMatch(out);
    final p = m == null ? 0 : int.parse(m.group(1)!);
    final fl = m == null ? 1 : int.parse(m.group(2)!);
    totalPass += p;
    totalFail += fl;
    final green = r.exitCode == 0 && fl == 0;
    stdout.writeln(
        '  ${green ? 'GREEN ' : 'RED   '} $name  pass=$p fail=$fl exit=${r.exitCode}');
    if (!green) {
      failedFiles.add(name);
      for (final line in out.split('\n')) {
        if (line.contains('FAIL') || line.contains('Error') || line.contains('  - ')) {
          stdout.writeln('        $line');
        }
      }
    }
  }

  stdout.writeln('\n===== 回归汇总 =====');
  stdout.writeln('功能测试文件: ${files.length}');
  stdout.writeln('用例总数:     ${totalPass + totalFail}');
  stdout.writeln('通过:         $totalPass');
  stdout.writeln('失败:         $totalFail');
  stdout.writeln('结论:         ${totalFail == 0 && failedFiles.isEmpty ? 'ALL_GREEN 全量通过' : 'FAILED 未通过'}');
  if (totalFail != 0 || failedFiles.isNotEmpty) {
    stdout.writeln('未通过文件: ${failedFiles.join(', ')}');
    exit(1);
  }
}

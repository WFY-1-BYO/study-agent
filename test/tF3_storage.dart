/// F3 · 本地存储与保存测试（PRD §4 F3 逐条验收）。
/// 单独运行：dart test/tF3_storage.dart
import 'dart:convert';

import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/storage.dart';

/// 故意写失败的后端，用于验证「保存失败不得静默吞错」。
class FailingStorage extends MemoryStorage {
  @override
  void write(String key, String value) => throw StateError('disk full');
}

/// 只保留非空实体，用于「数据无损」比较；
/// 格式完整性另用 entities.length == 13 单独断言（不放宽）。
Map<String, List<Map<String, dynamic>>> _nonEmpty(
        Map<String, List<Map<String, dynamic>>> src) =>
    Map<String, List<Map<String, dynamic>>>.fromEntries(
        src.entries.where((e) => e.value.isNotEmpty));

DataPackage _pack() => DataPackage(entities: {
      'tasks.json': [
        Task(id: 'T-1', type: 'habit', name: '背单词', timeHm: '07:30',
            reminderMode: 'vibration', leadMinutes: 2).toJson()
      ],
      'plans.json': [
        Plan(id: 'P-1', goal: '精进基本不等式', quantTarget: 0.75,
            startMode: 'immediate', createdDate: '2026-11-14').toJson()
      ],
    });

void runF3(Harness h) {
  h.group('F3 验收① 写入→重启→恢复一致', () {
    h.test('新建仓储实例（模拟重启）后数据完整恢复', () {
      final backend = MemoryStorage();
      final repo1 = LocalRepository(backend);
      repo1.saveNow(_pack());
      final repo2 = LocalRepository(backend);
      final restored = repo2.load();
      h.notNull(restored);
      h.jsonEq(_nonEmpty(restored!.entities), _nonEmpty(_pack().entities));
      h.eq(restored.entities.length, 13, '恢复后仍须为完整固定格式');
    });
    h.test('空仓储 load 返回 null 而不是造空数据', () {
      final repo = LocalRepository(MemoryStorage());
      h.isNull(repo.load());
      h.isNull(repo.readRawFiles());
    });
    h.test('多次保存以最后一次为准', () {
      final backend = MemoryStorage();
      final repo = LocalRepository(backend);
      final p1 = _pack();
      repo.saveNow(p1);
      final p2 = DataPackage(entities: {
        'tasks.json': [
          Task(id: 'T-2', type: 'once', name: '交作业', timeHm: '21:00',
              reminderMode: 'none').toJson()
        ],
      });
      repo.saveNow(p2);
      final restored = repo.load()!;
      h.jsonEq(_nonEmpty(restored.entities), _nonEmpty(p2.entities));
      h.eq(restored.entities.length, 13);
    });
  });

  h.group('F3 验收② 主动快照按阈值触发', () {
    h.test('累计 3 次变更才自动快照（默认阈值）', () {
      final backend = MemoryStorage();
      final repo = LocalRepository(backend);
      final p = _pack();
      repo.recordChange(p);
      repo.recordChange(p);
      h.eq(repo.snapshotCount, 0);
      h.eq(repo.pendingChanges, 2);
      h.isNull(repo.load(), '未达阈值时不应写入');
      repo.recordChange(p);
      h.eq(repo.snapshotCount, 1);
      h.eq(repo.pendingChanges, 0);
      h.notNull(repo.load());
    });
    h.test('自定义阈值生效（snapshotEvery=2）', () {
      final repo = LocalRepository(MemoryStorage(), snapshotEvery: 2);
      repo.recordChange(_pack());
      h.eq(repo.snapshotCount, 0);
      repo.recordChange(_pack());
      h.eq(repo.snapshotCount, 1);
    });
    h.test('snapshotEvery 非法值被拒绝', () {
      h.throwsValidation(() => LocalRepository(MemoryStorage(), snapshotEvery: 0));
      h.throwsValidation(() => LocalRepository(MemoryStorage(), snapshotEvery: -1));
    });
  });

  h.group('F3 验收③ 手动保存立即生效', () {
    h.test('saveNow 后立刻可 load，并清零变更计数', () {
      final repo = LocalRepository(MemoryStorage());
      repo.recordChange(_pack());
      h.eq(repo.pendingChanges, 1);
      repo.saveNow(_pack());
      h.eq(repo.manualSaveCount, 1);
      h.eq(repo.pendingChanges, 0);
      h.notNull(repo.load());
    });
    h.test('手动保存与自动快照各自计数独立', () {
      final repo = LocalRepository(MemoryStorage());
      repo.saveNow(_pack());
      repo.saveNow(_pack());
      h.eq(repo.manualSaveCount, 2);
      h.eq(repo.snapshotCount, 0);
      for (var i = 0; i < 3; i++) {
        repo.recordChange(_pack());
      }
      h.eq(repo.snapshotCount, 1);
    });
  });

  h.group('F3 验收④ 保存失败不得静默吞错', () {
    h.test('后端写失败时 saveNow 向上抛出', () {
      final repo = LocalRepository(FailingStorage());
      h.throwsOn(() => repo.saveNow(_pack()));
    });
    h.test('后端写失败时自动快照同样向上抛出', () {
      final repo = LocalRepository(FailingStorage());
      h.throwsOn(() {
        repo.recordChange(_pack());
        repo.recordChange(_pack());
        repo.recordChange(_pack());
      });
    });
  });

  h.group('F3 数据主权：本地格式就是开放 .studypack', () {
    h.test('backend 只有一个 key，内容是完整开放格式文件映射', () {
      final backend = MemoryStorage();
      LocalRepository(backend).saveNow(_pack());
      h.eq(backend.raw.length, 1);
      h.isTrue(backend.raw.containsKey(LocalRepository.stateKey));
      final files = LocalRepository(backend).readRawFiles()!;
      h.isTrue(files.containsKey('manifest.json'));
      h.eq(files.length, 14, '13 类实体 + manifest');
      h.contains(files['manifest.json']!, 'studypack-open-v1');
    });
    h.test('本地文件映射可直接交给外部读取（不锁死在 App 里）', () {
      final backend = MemoryStorage();
      LocalRepository(backend).saveNow(_pack());
      final files = LocalRepository(backend).readRawFiles()!;
      // 模拟「别的程序」直接读 tasks.json
      h.contains(files['tasks.json']!, '背单词');
      h.contains(files['plans.json']!, '基本不等式');
    });
    h.test('本地数据被篡改后 load 报错（校验链路生效）', () {
      final backend = MemoryStorage();
      LocalRepository(backend).saveNow(_pack());
      final files = LocalRepository(backend).readRawFiles()!;
      files['tasks.json'] = '[]';
      backend.write(LocalRepository.stateKey, jsonEncode(files));
      h.throwsValidation(() => LocalRepository(backend).load());
    });
  });
}

void main() {
  final h = Harness();
  runF3(h);
  h.report();
}

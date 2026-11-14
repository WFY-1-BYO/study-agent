/// 生成 F14 可运行查看器 web/index.html。
/// 用法：dart tools/gen_viewer.dart
library study_agent.tools.gen_viewer;

import 'dart:io';

import '../lib/ui.dart';
import '../lib/viewer.dart';

void main() {
  final state = UiState(
    tasks: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'T-1',
        'title': '打开不背单词 · 背单词（习惯性任务）',
        'type': 'habit',
        'reminderMode': 'vibration',
        'leadMinutes': 2,
      },
      <String, dynamic>{
        'id': 'T-2',
        'title': '数学 · 基本不等式专项',
        'type': 'once',
      },
    ],
    plans: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'P-1',
        'goal': '精进基本不等式，能解决 75% 相关题目',
        'quantTarget': 0.75,
        'passLine': 0.75,
        'deadlineDays': 15,
        'startMode': 'immediate',
      },
    ],
    slots: <Map<String, dynamic>>[
      <String, dynamic>{'id': 'S-1', 'start': '07:00', 'end': '07:30'},
      <String, dynamic>{'id': 'S-2', 'start': '13:00', 'end': '13:30'},
      <String, dynamic>{'id': 'S-3', 'start': '17:20', 'end': '18:20'},
      <String, dynamic>{'id': 'S-4', 'start': '21:30', 'end': '21:50'},
    ],
    sessions: <Map<String, dynamic>>[
      <String, dynamic>{'id': 'SE-1', 'stage': 'study'},
    ],
    weakPoints: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'WP-1',
        'knowledgeNodeId': 'RJ-A-BX1-CH2-2.2-EQ',
        'severity': 4,
      },
    ],
    aiNotes: <Map<String, dynamic>>[
      <String, dynamic>{'id': 'AN-1', 'owner': 'ai'},
    ],
    myNotes: <Map<String, dynamic>>[
      <String, dynamic>{'id': 'MN-1', 'owner': 'mine', 'channel': 'D'},
      <String, dynamic>{'id': 'MN-2', 'owner': 'mine', 'channel': 'C'},
    ],
    anchorLinks: <Map<String, dynamic>>[
      <String, dynamic>{
        'anchorId': 'RJ-A-BX1-CH2-2.2-EQ::SE-1::WP-1',
        'aiNoteIds': <String>['AN-1'],
        'myNoteIds': <String>['MN-1'],
      },
    ],
    resources: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'R-1',
        'source': '我的资料·基本不等式讲义.pdf',
      },
    ],
  );

  final html = HtmlRenderer.render(state);
  final dir = Directory('web');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final out = File('web/index.html');
  out.writeAsStringSync(html);
  stdout.writeln('已生成 ${out.path}（${html.length} 字符，UTF-8）');
}

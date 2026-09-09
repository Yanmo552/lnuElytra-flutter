import 'package:flutter_test/flutter_test.dart';
import 'package:lnu_elytra/services/multi_spawn.dart';

void main() {
  test('解析带表头的表格，忽略微信名和说明列', () {
    final text = [
      '学号\t密码(默认身份证后六位，能登上就不用改)\t志愿一\t志愿二\t志愿三\t微信名（这样我就能知道哪个是你）',
      '演示不要填\t大家不要填错了，确认自己的账号密码正确和所选的课程号正确，出错了，没办法的呢\t\t\t\t',
      '202603114227\t200711189523Zz@\t77102601-74\t77102601-75\t77102601-73\t橘祎',
      '202615504214\tLzq1203717.\t羽毛球\t匹克球\t\tLiiizq',
      '202611964203\tFg888015@@\t身体拓展\t匹克球\t飞镖\tok',
      '202602164129\t1qazbmko0\t77102601-88\t\t\t俗人',
      '202616884324\tPanhui1031.\t77102601-39 \t77102601-40\t77102601-38\t',
      '202612444131\tA20080720wxw@\t\t\t\t',
      '202612444140\tZhongaodi5238!\t\t\t\t嘻😁',
      '202615504223\tR\u2006o\u2006061014\u2006y\u2006y\t"77102601-0166 【韩乾乾】\n"\t"-77102601-0161 【陈燕2】\n讲师"\t"77102601-0163 【黄凤萍】\n助教"\t111瑜',
      '202603114110\tDwthxlgdf1204?\t(2026-2027-1)-77102601-86\t(2026-2027-1)-77102601-0173\t(2026-2027-1)-77102601-82\t兩課星的軌道',
      '202615504215\t@ZjZyz070904\t(2026-2027-1)-77102601-85\t(2026-2027-1)-77102601-85\t\t祎只小白',
    ].join('\n');
    final rows = MultiSpawn.parseRows(text);
    expect(rows.length, 8);
    final first = rows.firstWhere((r) => r['username'] == '202603114227');
    expect(first['courses'], '77102601-74,77102601-75,77102601-73');
    final sport = rows.firstWhere((r) => r['username'] == '202615504214');
    expect(sport['courses'], '羽毛球,匹克球');
    final okRow = rows.firstWhere((r) => r['username'] == '202611964203');
    expect(okRow['courses'], '身体拓展,匹克球,飞镖');
    final messy = rows.firstWhere((r) => r['username'] == '202615504223');
    expect(messy['courses'], '77102601-0166,77102601-0161,77102601-0163');
    final dup = rows.firstWhere((r) => r['username'] == '202615504215');
    expect(dup['courses'], '(2026-2027-1)-77102601-85');
    expect(rows.any((r) => r['username'] == '202612444131'), false);
    expect(rows.any((r) => r['username'] == '202612444140'), false);
  });

  test('无表头时按位置解析，URL 列识别为服务器', () {
    final text = [
      '202543401056\tlili111213\t大学体育3（瑜伽）-0001,美术鉴赏-0007',
      '202530412016\txyw200724\t影视鉴赏-0007\thttp://newjw.lj-edu.cn/jwglxt\t通识选修课',
    ].join('\n');
    final rows = MultiSpawn.parseRows(text);
    expect(rows.length, 2);
    expect(rows[0]['server'], '');
    expect(rows[1]['server'], 'http://newjw.lj-edu.cn/jwglxt');
    expect(rows[1]['tab'], '通识选修课');
    expect(rows[1]['courses'], '影视鉴赏-0007');
  });

  test('Excel 粘贴的多行单元格（带引号）不拆断行', () {
    final text = [
      '学号\t密码\t志愿一\t志愿二',
      '202615504223\tRo061014yy\t"77102601-0166 【韩乾乾】\n"\t"-77102601-0161 【陈燕2】\n讲师"',
    ].join('\n');
    final rows = MultiSpawn.parseRows(text);
    expect(rows.length, 1);
    expect(rows.first['username'], '202615504223');
    expect(rows.first['courses'], '77102601-0166,77102601-0161');
  });

  test('说明行（含"账号密码""课程号"字样）不会被误认为表头', () {
    final text = [
      '演示不要填\t大家不要填错了，确认自己的账号密码正确和所选的课程号正确，出错了，没办法的呢\t\t\t',
      '202602164129\t145746\t77102601-88\t77102601-0101\t\t俗人\tok',
      '202603664120\t20080201srkl\t77102601-69\t77102601-62\t77102601-63\t\t',
    ].join('\n');
    final rows = MultiSpawn.parseRows(text);
    expect(rows.length, 2);
    final a = rows.firstWhere((r) => r['username'] == '202602164129');
    expect(a['password'], '145746');
    expect(a['courses']!.startsWith('77102601-88,77102601-0101'), true);
    final b = rows.firstWhere((r) => r['username'] == '202603664120');
    expect(b['courses'], '77102601-69,77102601-62,77102601-63');
  });

  test('不带引号的多行单元格（首列为空的续行）合并回上一行', () {
    final text = [
      '学号\t密码\t志愿一\t志愿二\t志愿三\t微信名',
      '202615504223\tRo061014yy\t77102601-0166\n\t77102601-0161\t77102601-0163\t111瑜',
    ].join('\n');
    final rows = MultiSpawn.parseRows(text);
    expect(rows.length, 1);
    expect(rows.first['username'], '202615504223');
    expect(rows.first['courses'], '77102601-0166,77102601-0161,77102601-0163');
  });

  test('Markdown 表格（| a | b |）也能解析', () {
    final text = [
      '| 学号 | 密码 | 志愿一 | 志愿二 |',
      '| --- | --- | --- | --- |',
      '| 202603114227 | 200711189523Zz@ | 77102601-74 | 77102601-75 |',
      '| 202615504214 | Lzq1203717. | 77102601-0163 | 77102601-0166 |',
    ].join('\n');
    final rows = MultiSpawn.parseRows(text);
    expect(rows.length, 2);
    expect(rows[0]['username'], '202603114227');
    expect(rows[0]['courses'], '77102601-74,77102601-75');
    expect(rows[1]['username'], '202615504214');
    expect(rows[1]['courses'], '77102601-0163,77102601-0166');
  });
}

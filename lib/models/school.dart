/// 学校选课页标签页（部分学校有多个标签，如丽江师范学院）
class SchoolTab {
  final String id; // xkkz_id（隐藏表单字段）
  final String name; // 中文名
  const SchoolTab(this.id, this.name);
}

/// 学校配置：服务器地址 + 标签页
class School {
  final String id;
  final String name;
  final String server;
  final List<SchoolTab> tabs; // 空 = 无需切换标签
  const School({
    required this.id,
    required this.name,
    required this.server,
    this.tabs = const [],
  });

  bool get hasTabs => tabs.isNotEmpty;
}

/// 预设学校列表
const List<School> kPresetSchools = [
  School(id: 'lingnan', name: '岭南师范学院', server: 'http://jw.lingnan.edu.cn'),
  School(
    id: 'lijiang',
    name: '丽江师范学院',
    server: 'http://newjw.lj-edu.cn/jwglxt',
    tabs: [
      SchoolTab('54FC1FF9A3362073E06371D2A8C0AD3A', '板块课(大学体育3（本科）)'),
      SchoolTab('54FB211AA28C06F3E06370D2A8C08E99', '板块课(本科班艺术课程)'),
      SchoolTab('54FC1FF9A35A2073E06371D2A8C0AD3A', '板块课(公共艺术课程（2025版）)'),
      SchoolTab('54FC39B26F3B2436E06371D2A8C0EF8F', '板块课(大学体育3)'),
      SchoolTab('54FB211AA25206F3E06370D2A8C08E99', '通识选修课'),
      SchoolTab('54E788F21E323231E06370D2A8C01FAA', '专业选修课'),
    ],
  ),
  School(id: 'shandong', name: '山东青年政治学院', server: 'https://jw.sdyu.edu.cn/jwglxt'),
  School(id: 'gcc', name: '广州商学院', server: 'http://jwxt.gcc.edu.cn'),
  School(
    id: 'huanggang',
    name: '黄冈师范学院',
    server: 'http://211.69.159.74/jwglxt',
    tabs: [
      SchoolTab('5A8B57941778E392E063E80C1FAC7FD7', '通识选修课'),
      SchoolTab('5A7778E9017E6A82E063E80C1FACBA6F', '体育分项'),
      SchoolTab('5A623C9565FDE248E063E80C1FAC1370', '英语分项'),
    ],
  ),
];

School? schoolById(String id) {
  for (final s in kPresetSchools) {
    if (s.id == id) return s;
  }
  return null;
}

School? schoolByServer(String server) {
  final norm = server.trim().replaceAll(RegExp(r'/+$'), '');
  for (final s in kPresetSchools) {
    if (s.server.trim().replaceAll(RegExp(r'/+$'), '') == norm) return s;
  }
  return null;
}

/// 构造自定义学校（服务器地址 + 可选标签）
School customSchool(String server, {List<SchoolTab> tabs = const []}) {
  return School(id: 'custom', name: '自定义学校', server: server.trim(), tabs: tabs);
}

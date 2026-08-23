enum AppDestination {
  home,
  capture,
  claims,
  plan,
  tasks,
  review,
  settings,
}

extension AppDestinationLabel on AppDestination {
  String get label => switch (this) {
        AppDestination.home => '首页',
        AppDestination.capture => '记录观察',
        AppDestination.claims => '审阅结论',
        AppDestination.plan => '行动计划',
        AppDestination.tasks => '任务',
        AppDestination.review => '复盘',
        AppDestination.settings => '设置',
      };
}

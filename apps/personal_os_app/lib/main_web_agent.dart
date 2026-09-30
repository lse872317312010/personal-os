import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/link.dart';

import 'src/agent_interop/automatic_agent_gateway.dart';
import 'src/agent_interop/local_agent_event_store.dart';
import 'src/app.dart';
import 'src/composition/app_composition.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Start());
}

final class _Start extends StatefulWidget {
  const _Start();
  @override
  State<_Start> createState() => _StartState();
}

final class _StartState extends State<_Start> {
  AppComposition? _app;
  String? _error;
  bool _fontReady = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final font = await http
          .get(Uri.base.resolve('fonts/NotoSansSC.ttf'))
          .timeout(const Duration(seconds: 30));
      if (font.statusCode != 200) {
        throw const FormatException('bundled_font_missing');
      }
      final loader = FontLoader('PersonalSC');
      loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(font.bodyBytes)));
      await loader.load();
      _fontReady = true;
      if (Uri.base.host != '127.0.0.1') {
        if (mounted) {
          setState(
              () => _error = '下载并启动本机版，登录你的 ChatGPT。之后计划、复盘和下一轮都在应用内自动完成。');
        }
        return;
      }
      final gateway = LocalAutomaticAgentGateway(origin: Uri.base);
      await gateway.status();
      final store = LocalAgentEventStore(gateway);
      await store.load();
      final app =
          AppComposition.localAgent(gateway: gateway, eventStore: store);
      if (mounted) setState(() => _app = app);
    } on Object {
      if (mounted) {
        setState(() => _error = _fontReady
            ? '本机服务未启动或历史记录无法读取。请重新启动 Personal OS 本机版。'
            : 'Unable to load app resources. Please restart Personal OS.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => _app != null
      ? PersonalOsApp(composition: _app!)
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              fontFamily: 'PersonalSC',
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xff315c4c)),
              useMaterial3: true),
          home: Scaffold(
              body: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                const Icon(Icons.auto_awesome,
                                    size: 56, color: Color(0xff315c4c)),
                                const SizedBox(height: 24),
                                Text(
                                    _fontReady
                                        ? 'Personal OS\nAI 帮你想，你负责行动'
                                        : 'Personal OS',
                                    style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 16),
                                Text(_error ?? 'Loading…',
                                    style: const TextStyle(height: 1.6)),
                                const SizedBox(height: 24),
                                if (_error == null)
                                  const LinearProgressIndicator(),
                                if (_error != null &&
                                    Uri.base.host != '127.0.0.1') ...<Widget>[
                                  Link(
                                      uri: Uri.parse(
                                          'https://github.com/lse872317312010/personal-os/releases/tag/automatic-agent-web'),
                                      target: LinkTarget.blank,
                                      builder: (context, follow) =>
                                          FilledButton(
                                              onPressed: follow,
                                              child: const Text('下载自动版'))),
                                  const SizedBox(height: 12),
                                  const Text(
                                      'Windows：解压后双击 Start-Personal-OS.cmd。浏览器会自动打开应用。'),
                                ],
                                if (_error != null &&
                                    Uri.base.host == '127.0.0.1')
                                  FilledButton(
                                      onPressed: _load,
                                      child: const Text('重新连接')),
                              ]))))),
        );
}

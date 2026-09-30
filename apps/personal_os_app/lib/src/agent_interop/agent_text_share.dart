import 'package:flutter/services.dart';

abstract interface class AgentTextSharePort {
  Future<void> share(String text);
}

/// Sends text through Android's system chooser without binding Personal OS to
/// a specific assistant or Harness.
final class MethodChannelAgentTextShare implements AgentTextSharePort {
  const MethodChannelAgentTextShare({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'personal_os/agent_text_share';

  final MethodChannel _channel;

  @override
  Future<void> share(String text) async {
    await _channel.invokeMethod<void>(
      'shareText',
      <String, Object?>{'text': text},
    );
  }
}

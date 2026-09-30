import 'package:flutter/foundation.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import '../agent_interop/agent_handoff.dart';
import '../agent_interop/automatic_agent_gateway.dart';
import 'strategy_loop_controller.dart';

final class AutomaticAgentController extends ChangeNotifier {
  AutomaticAgentController({required this.strategy, required this.gateway});
  final StrategyLoopController strategy;
  final AutomaticAgentGateway gateway;
  bool connected = false;
  bool busy = false;
  String provider = 'chatgpt';
  String? model;
  String? account;
  List<Map<String, Object?>> accounts = <Map<String, Object?>>[];
  List<Map<String, Object?>> models = <Map<String, Object?>>[];
  String? error;
  int _epoch = 0;
  bool _disposed = false;
  String? _requestFingerprint;
  bool get canGenerate =>
      connected &&
      model != null &&
      !busy &&
      strategy.status != StrategyUiStatus.running &&
      strategy.personalGoal != null &&
      !strategy.hasPendingProposal &&
      !strategy.canActivate &&
      !strategy.hasPendingReview &&
      (!strategy.hasSession || strategy.canRequestAgent);
  Future<void> connect() async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final state = await gateway.status();
      final catalog = state['connected'] == true
          ? await gateway.models()
          : <Map<String, Object?>>[];
      if (!_current(epoch)) return;
      connected = state['connected'] == true;
      provider = state['provider'] as String;
      account = state['account'] as String?;
      accounts = ((state['accounts'] as List?) ?? <Object?>[])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      models = catalog;
      if (!models.any((e) => e['id'] == model))
        model = models.isEmpty ? null : models.first['id'] as String;
    } on Object {
      if (_current(epoch)) error = '无法连接本机 AI 服务。请启动 Personal OS 本机版。';
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void selectModel(String? value) {
    if (!busy && models.any((e) => e['id'] == value)) {
      model = value;
      notifyListeners();
    }
  }

  Future<void> selectAccount(String id) async {
    if (busy) return;
    await gateway.post('/api/auth/select', <String, Object?>{'account_id': id});
    await connect();
  }

  Future<void> logout() async {
    if (busy) return;
    final result = await gateway.post('/api/auth/logout', <String, Object?>{});
    await connect();
    if (result['revoked'] != true && !_disposed) {
      error = '已在本机退出。远端撤销未确认，可在 ChatGPT 设置中断开此应用。';
      notifyListeners();
    }
  }

  Future<void> generate() async {
    if (!canGenerate || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!strategy.hasSession)
        await strategy.openOfflineSession(agentId: 'automatic-$provider');
      if (!_current(epoch)) return;
      await strategy.refreshContextForHandoff();
      if (!_current(epoch)) return;
      if (strategy.status == StrategyUiStatus.failed ||
          strategy.contextBundle == null)
        throw const AgentGatewayException('context_unavailable');
      final context = strategy.contextBundle!,
          session = strategy.sessionId,
          strategyId = strategy.strategyId;
      final stage = agentHandoffStage(context, strategyId: strategyId);
      final fingerprint =
          '$session:$strategyId:${strategy.outcomeId}:${strategy.reviewState}:$stage';
      if (_requestFingerprint == fingerprint) return;
      final reply = await gateway.request(
          model: model!,
          prompt: buildAgentHandoffPrompt(context, strategyId: strategyId),
          context: context,
          stage: stage.name);
      if (!_current(epoch) ||
          strategy.sessionId != session ||
          strategy.strategyId != strategyId ||
          strategy.contextBundle != context) return;
      final parsed = parseAgentHandoffReply(reply);
      if ((stage == AgentHandoffStage.review) !=
          (parsed.kind == AgentReplyKind.review))
        throw const AgentGatewayException('invalid_agent_bundle');
      if (parsed.kind == AgentReplyKind.review) {
        await strategy.importReview(parsed.bundleJson);
      } else {
        await strategy.importProposal(parsed.bundleJson);
      }
      if (!_current(epoch)) return;
      if (strategy.status == StrategyUiStatus.failed)
        throw const AgentGatewayException('invalid_agent_bundle');
      _requestFingerprint = fingerprint;
    } on Object catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveOutcome(String observation) async {
    if (busy || observation.trim().isEmpty) return;
    final epoch = _epoch;
    await strategy.recordOutcome(
        observation: observation, valence: OutcomeValence.mixed);
    if (_current(epoch) && strategy.status != StrategyUiStatus.failed)
      await generate();
  }

  Future<void> decideReview(ReviewDecision decision) async {
    if (busy) return;
    final epoch = _epoch;
    await strategy.decideReview(decision);
    if (_current(epoch) &&
        strategy.status != StrategyUiStatus.failed &&
        decision == ReviewDecision.accept) await generate();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void reset() {
    _epoch++;
    gateway.cancel();
    connected = false;
    busy = false;
    models = [];
    model = null;
    account = null;
    accounts = [];
    error = null;
    _requestFingerprint = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    gateway.cancel();
    super.dispose();
  }

  String _message(Object failure) {
    final code = failure is AgentGatewayException
        ? failure.code
        : 'invalid_agent_bundle';
    return switch (code) {
      'sign_in_required' ||
      'invalid_grant' ||
      'invalid_api_key' =>
        'AI 连接需要重新授权。请在连接设置中登录。',
      'subscription_sharing_usage_limit_exceeded' ||
      'subscription_sharing_usage_unavailable' ||
      'insufficient_quota' ||
      'rate_limit_exceeded' =>
        '当前 AI 额度不足或暂不可用，请查看用量后重试。',
      'provider_response_interrupted' ||
      'provider_response_incomplete' ||
      'provider_request_cancelled' =>
        'AI 回复未完成，已有计划已保留。请重试。',
      'provider_refused' => 'AI 没有提供可执行计划，请调整目标后重试。',
      'invalid_agent_bundle' => 'AI 回复未通过行动计划校验，请重新生成。',
      _ => 'AI 请求失败，已有计划已保留。请检查连接后重试。',
    };
  }
}

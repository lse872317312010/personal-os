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
  bool checkingConnection = false;
  bool savingFeedback = false;
  String? connectionCheckMessage;
  String provider = 'chatgpt';
  String? model;
  String? account;
  List<Map<String, Object?>> accounts = <Map<String, Object?>>[];
  List<Map<String, Object?>> models = <Map<String, Object?>>[];
  List<Map<String, Object?>> connections = <Map<String, Object?>>[];
  String? connectionId, connectionName;
  String? error;
  int _epoch = 0;
  bool _disposed = false;
  String? _requestFingerprint;
  String? _resumeAttemptKey;
  String? _connectionRevision;
  bool get hasPendingContinuation =>
      strategy.hasSession &&
      strategy.personalGoal != null &&
      (strategy.strategyId == null ||
          (strategy.strategyState == 'active' &&
              strategy.outcomeId != null &&
              (strategy.reviewState == null ||
                  strategy.reviewState == 'accepted')));

  String? get _pendingResumeKey {
    if (!hasPendingContinuation || strategy.contextBundle == null) return null;
    final refs = strategy.contextRecords
        .map((record) => '${record['ref']}')
        .toList()
      ..sort();
    return '${strategy.sessionId}:${strategy.strategyId}:${strategy.outcomeId}:'
        '${strategy.reviewState}:$provider:$connectionId:$_connectionRevision:$account:$model:$refs';
  }

  /// One automatic attempt per pending state and connection in this app instance.
  /// User decisions are never inferred from a restored draft or rejection.
  Future<bool> resumePending() async {
    if (_disposed || !canGenerate) return false;
    final key = _pendingResumeKey;
    if (key == null || key == _resumeAttemptKey) return false;
    return _generate(automatic: true);
  }

  Future<bool> reconnectAndResume({bool retryPending = false}) async {
    if (busy || _disposed || strategy.status == StrategyUiStatus.running) {
      return false;
    }
    final epoch = _epoch;
    final previousKey = _pendingResumeKey, previousError = error;
    await connect();
    if (!_current(epoch)) return false;
    if (retryPending) _resumeAttemptKey = null;
    final attempted = await resumePending();
    if (_current(epoch) &&
        !attempted &&
        previousKey != null &&
        previousKey == _pendingResumeKey &&
        error == null &&
        previousError != null) {
      error = previousError;
      notifyListeners();
    }
    return attempted;
  }

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
    connectionCheckMessage = null;
    notifyListeners();
    try {
      final state = await gateway.status();
      if (!_current(epoch)) return;
      connected = state['connected'] == true;
      provider = state['provider'] as String;
      account = state['account'] as String?;
      accounts = ((state['accounts'] as List?) ?? <Object?>[])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      connections = ((state['connections'] as List?) ?? <Object?>[])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      connectionId = state['connection_id'] as String?;
      _connectionRevision = state['connection_revision'] as String?;
      connectionName = state['connection_name'] as String?;
      final catalog =
          connected ? await gateway.models() : <Map<String, Object?>>[];
      if (!_current(epoch)) return;
      models = catalog;
      if (!models.any((e) => e['id'] == model)) {
        model = models.isEmpty ? null : models.first['id'] as String;
      }
    } on Object catch (failure) {
      if (_current(epoch)) {
        connected = false;
        models = [];
        model = null;
        error = _message(failure);
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void selectModel(String? value) {
    if (!busy && models.any((e) => e['id'] == value)) {
      if (model != value) _resumeAttemptKey = null;
      model = value;
      connectionCheckMessage = null;
      notifyListeners();
    }
  }

  Future<void> checkConnection() async {
    if (busy ||
        _disposed ||
        !connected ||
        model == null ||
        strategy.status == StrategyUiStatus.running) {
      return;
    }
    final epoch = _epoch;
    busy = true;
    checkingConnection = true;
    connectionCheckMessage = null;
    error = null;
    notifyListeners();
    try {
      final result = await gateway.checkConnection(model: model!);
      if (!_current(epoch)) return;
      if (result['ok'] != true || result['model'] != model) {
        throw const AgentGatewayException('invalid_provider_response');
      }
      connectionCheckMessage = 'AI 服务已响应。';
    } on Object catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        checkingConnection = false;
        notifyListeners();
      }
    }
  }

  Future<bool> saveConnection(Map<String, Object?> value) =>
      _changeConnection('/api/agent/connections', value);
  Future<bool> selectConnection(String id) => _changeConnection(
      '/api/agent/connections/select', <String, Object?>{'connection_id': id});
  Future<bool> removeConnection(String id) => _changeConnection(
      '/api/agent/connections/remove', <String, Object?>{'connection_id': id});
  Future<bool> _changeConnection(
      String path, Map<String, Object?> value) async {
    if (busy || _disposed || strategy.status == StrategyUiStatus.running) {
      return false;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await gateway.post(path, value);
      if (!_current(epoch)) return false;
      _requestFingerprint = null;
      _resumeAttemptKey = null;
      busy = false;
      await connect();
      return _current(epoch);
    } on Object catch (failure) {
      if (_current(epoch)) error = _message(failure);
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectAccount(String id) async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    notifyListeners();
    try {
      await gateway
          .post('/api/auth/select', <String, Object?>{'account_id': id});
      if (!_current(epoch)) return;
      _resumeAttemptKey = null;
      busy = false;
      await connect();
    } on Object catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    notifyListeners();
    try {
      final result =
          await gateway.post('/api/auth/logout', <String, Object?>{});
      if (!_current(epoch)) return;
      busy = false;
      await connect();
      if (result['revoked'] != true && _current(epoch)) {
        error = '已在本机退出。远端撤销未确认，可在 ChatGPT 设置中断开此应用。';
      }
    } on Object catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> generate() async {
    await _generate();
  }

  Future<bool> _generate({bool automatic = false}) async {
    if (!canGenerate || _disposed) return false;
    final epoch = _epoch;
    final previousError = error;
    var requested = false;
    busy = true;
    error = null;
    connectionCheckMessage = null;
    notifyListeners();
    try {
      if (!strategy.hasSession) {
        await strategy.openOfflineSession(agentId: 'automatic-agent-gateway');
      }
      if (!_current(epoch)) return false;
      await strategy.refreshContextForHandoff();
      if (!_current(epoch)) return false;
      if (strategy.status == StrategyUiStatus.failed ||
          strategy.contextBundle == null) {
        throw const AgentGatewayException('context_unavailable');
      }
      final context = strategy.contextBundle!,
          session = strategy.sessionId,
          strategyId = strategy.strategyId;
      final stage = agentHandoffStage(context, strategyId: strategyId);
      if (automatic) {
        final key = _pendingResumeKey;
        if (key == null || key == _resumeAttemptKey) {
          error = previousError;
          return false;
        }
        _resumeAttemptKey = key;
      }
      final fingerprint =
          '$session:$strategyId:${strategy.outcomeId}:${strategy.reviewState}:$stage';
      if (_requestFingerprint == fingerprint) return false;
      requested = true;
      final reply = await gateway.request(
          model: model!,
          prompt: buildAgentHandoffPrompt(context, strategyId: strategyId),
          context: context,
          stage: stage.name);
      if (!_current(epoch) ||
          strategy.sessionId != session ||
          strategy.strategyId != strategyId ||
          strategy.contextBundle != context) {
        return false;
      }
      final parsed = parseAgentHandoffReply(reply);
      if ((stage == AgentHandoffStage.review) !=
          (parsed.kind == AgentReplyKind.review)) {
        throw const AgentGatewayException('invalid_agent_bundle');
      }
      if (parsed.kind == AgentReplyKind.review) {
        await strategy.importReview(parsed.bundleJson);
      } else {
        await strategy.importProposal(parsed.bundleJson);
      }
      if (!_current(epoch)) return false;
      if (strategy.status == StrategyUiStatus.failed) {
        throw const AgentGatewayException('invalid_agent_bundle');
      }
      _requestFingerprint = fingerprint;
      connectionCheckMessage = '最近一次 AI 请求已完成。';
    } on Object catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
    return requested && _current(epoch);
  }

  Future<void> saveFeedback(ExecutionStatus status, {String note = ''}) async {
    if (busy ||
        _disposed ||
        strategy.status == StrategyUiStatus.running ||
        !strategy.canRecordExecution ||
        strategy.executionId != null ||
        strategy.outcomeId != null) {
      return;
    }
    final epoch = _epoch;
    busy = true;
    savingFeedback = true;
    error = null;
    notifyListeners();
    try {
      await strategy.recordFeedback(executionStatus: status, note: note);
    } finally {
      if (_current(epoch)) {
        busy = false;
        savingFeedback = false;
        notifyListeners();
      }
    }
    if (_current(epoch) &&
        strategy.status != StrategyUiStatus.failed &&
        strategy.outcomeId != null) {
      await generate();
    }
  }

  Future<void> saveOutcome(String observation) async {
    if (busy ||
        _disposed ||
        strategy.status == StrategyUiStatus.running ||
        !strategy.canRecordOutcome ||
        strategy.outcomeId != null ||
        observation.trim().isEmpty) {
      return;
    }
    final epoch = _epoch;
    busy = true;
    savingFeedback = true;
    error = null;
    notifyListeners();
    try {
      await strategy.recordOutcome(
          observation: observation, valence: OutcomeValence.neutral);
    } finally {
      if (_current(epoch)) {
        busy = false;
        savingFeedback = false;
        notifyListeners();
      }
    }
    if (_current(epoch) &&
        strategy.status != StrategyUiStatus.failed &&
        strategy.outcomeId != null) {
      await generate();
    }
  }

  Future<void> decideReview(ReviewDecision decision) async {
    if (busy) return;
    final epoch = _epoch;
    await strategy.decideReview(decision);
    if (_current(epoch) &&
        strategy.status != StrategyUiStatus.failed &&
        decision == ReviewDecision.accept) {
      await generate();
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void reset() {
    _epoch++;
    gateway.cancel();
    connected = false;
    busy = false;
    checkingConnection = false;
    savingFeedback = false;
    connectionCheckMessage = null;
    models = [];
    model = null;
    account = null;
    accounts = [];
    connections = [];
    connectionId = null;
    connectionName = null;
    error = null;
    _requestFingerprint = null;
    _resumeAttemptKey = null;
    _connectionRevision = null;
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
        'AI 授权已失效，请在连接设置中重新登录或更新密钥。',
      'invalid_provider_endpoint' =>
        '服务地址需使用 HTTPS；本机服务可使用 http://127.0.0.1。请勿在地址中填写密钥。',
      'connection_check_timeout' => 'AI 服务在 30 秒内没有完成测试，请检查服务状态后重试。',
      'provider_unreachable' => '无法访问 AI 服务，请检查地址、网络和服务是否已启动。',
      'provider_request_failed' => 'AI 服务未能完成请求，请检查模型权限和密钥后重试。',
      'connection_name_required' => '请给这个连接起一个名字。',
      'connection_model_required' => '请填写服务提供的模型名称。',
      'invalid_connection' => '连接配置无效，请检查名称、模型和地址。',
      'connection_limit' => '已保存的连接太多，请先删除不用的连接。',
      'connection_changed' => 'AI 连接已在另一页面切换，请刷新连接后重试。',
      'connection_not_found' => '此连接已被移除，请重新选择。',
      'local_service_unavailable' ||
      'service_unavailable' ||
      'connection_settings_unavailable' =>
        '无法连接本机 AI 服务。请启动 Personal OS 本机版。',
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

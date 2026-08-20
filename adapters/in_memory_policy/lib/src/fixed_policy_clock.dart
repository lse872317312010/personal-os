import 'package:personal_os_policy_application/policy_application.dart';

/// Deterministic policy time source for composition tests and local spikes.
final class FixedPolicyClock implements PolicyClock {
  FixedPolicyClock(DateTime value) : _value = value.toUtc();

  final DateTime _value;

  @override
  DateTime now() => _value;
}

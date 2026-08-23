import 'package:personal_os_domain/domain.dart';

import 'risk.dart';

PolicyDecision authorizePersistence(Sensitivity sensitivity) =>
    sensitivity == Sensitivity.d4
        ? PolicyDecision.denied(PolicyReason.d4PersistenceForbidden)
        : PolicyDecision.allowed();

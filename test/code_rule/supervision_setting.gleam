//// The supervision-setting rules: every supervisor in `src/` states its
//// restart limit, and every worker states its shutdown time, so no setting
//// is a library default nobody chose.

import code_rule/source.{type Breach, type SourceFile}

/// Each supervisor builder in the file whose pipeline does not set a restart
/// limit. A builder is a call of `static_supervisor.new`, or of
/// `factory_supervisor.worker_child` or `factory_supervisor.supervisor_child`;
/// its pipeline states the limit with the same module's `restart_tolerance`.
pub fn missing_restart_limit(file: SourceFile) -> List(Breach) {
  todo as "find the supervisor builders with no restart_tolerance in their pipeline"
}

/// Each worker in the file whose pipeline does not set a shutdown time. A
/// worker is a call of `supervision.worker` or of
/// `factory_supervisor.worker_child`; its pipeline states the time with
/// `supervision.timeout` or `factory_supervisor.timeout` of the same kind.
pub fn missing_shutdown_time(file: SourceFile) -> List(Breach) {
  todo as "find the workers with no timeout in their pipeline"
}

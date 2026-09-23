class Live {
  const Live();
}

class LiveStore {
  const LiveStore();
}

class Computed {
  const Computed();
}

const computed = Computed();

/// Opts a mutable object-typed field out of deep tracking.
///
/// By default, `@Live()` / `@LiveStore()` wrap such fields in a generated
/// `_Live<Type>` proxy so that mutations *inside* the object trigger a
/// rebuild. Fields annotated with `@untracked` are treated as plain
/// reassignable fields instead: assigning the field still triggers a rebuild,
/// but mutating the object's own fields does not (call `notify()` for that).
class Untracked {
  const Untracked();
}

const untracked = Untracked();

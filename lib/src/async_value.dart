abstract class AsyncValue<T> {
  const AsyncValue();
}

class AsyncLoading<T> extends AsyncValue<T> {
  const AsyncLoading();
}

class AsyncData<T> extends AsyncValue<T> {
  const AsyncData(this.value);
  final T value;
}

class AsyncError<T> extends AsyncValue<T> {
  const AsyncError(this.error, [this.stackTrace = StackTrace.empty]);
  final Object error;
  final StackTrace stackTrace;
}

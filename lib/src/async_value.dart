sealed class AsyncValue<T> {}

final class AsyncLoading<T> extends AsyncValue<T> {
  const AsyncLoading();
}

final class AsyncData<T> extends AsyncValue<T> {
  const AsyncData(this.value);
  final T value;
}

final class AsyncError<T> extends AsyncValue<T> {
  const AsyncError(this.error, [this.stackTrace = StackTrace.empty]);
  final Object error;
  final StackTrace stackTrace;
}

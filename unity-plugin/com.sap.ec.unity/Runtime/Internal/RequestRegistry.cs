using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Tracks pending native calls by monotonically-increasing request id.
    ///
    /// Every async <c>ec_*</c> entry receives an id; the corresponding
    /// <see cref="TaskCompletionSource{TResult}"/> is resolved from
    /// <see cref="CallbackDispatchers.OnCompletion"/> once the shim fires its
    /// completion callback. The registry is thread-safe; native completions
    /// can arrive on arbitrary threads.
    ///
    /// Result payload convention: the string handed to
    /// <see cref="Resolve"/> is either <c>null</c> (void success), or the
    /// UTF-8-decoded JSON envelope from the shim. Callers deserialize with
    /// <c>System.Text.Json</c>.
    /// </summary>
    internal static class RequestRegistry
    {
        private static int s_nextId = 0;
        private static readonly ConcurrentDictionary<int, TaskCompletionSource<string>> s_pending
            = new ConcurrentDictionary<int, TaskCompletionSource<string>>();

        /// <returns>The new id and a task that will complete when the shim
        /// finishes the call.</returns>
        internal static (int id, TaskCompletionSource<string> tcs) Register()
        {
            var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            int id = Interlocked.Increment(ref s_nextId);
            s_pending[id] = tcs;
            return (id, tcs);
        }

        internal static void Resolve(int id, string resultJson)
        {
            if (s_pending.TryRemove(id, out var tcs))
            {
                tcs.TrySetResult(resultJson);
            }
        }

        internal static void Fail(int id, System.Exception error)
        {
            if (s_pending.TryRemove(id, out var tcs))
            {
                tcs.TrySetException(error);
            }
        }
    }
}

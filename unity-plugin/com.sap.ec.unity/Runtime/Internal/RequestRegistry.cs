using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Maps request ids to their <see cref="TaskCompletionSource{TResult}"/>. Ids are minted with
    /// <see cref="Interlocked.Increment(ref int)"/> so they are unique across every P/Invoke call
    /// for the process lifetime; the shim quotes back the same id in its completion callback.
    /// The registry is thread-safe: <see cref="Register"/> may be called from any thread, and
    /// <see cref="Resolve"/> runs on the main-thread pump (see <see cref="MainThreadPump"/>).
    /// </summary>
    internal static class RequestRegistry
    {
        private static int s_nextId;
        private static readonly ConcurrentDictionary<int, TaskCompletionSource<string>> s_pending
            = new ConcurrentDictionary<int, TaskCompletionSource<string>>();

        /// <summary>
        /// Reserve a fresh request id and its future. The caller passes <c>id</c> to the shim
        /// entry point and awaits <c>tcs.Task</c>; the result string is the shim's UTF-8 JSON
        /// (or <c>null</c> for methods that return no payload).
        /// </summary>
        public static (int id, TaskCompletionSource<string> tcs) Register()
        {
            int id = Interlocked.Increment(ref s_nextId);
            // RunContinuationsAsynchronously → continuations don't run inline on the pump thread
            // that resolved the TCS, avoiding surprise re-entry when a caller awaits back-to-back.
            var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            if (!s_pending.TryAdd(id, tcs))
            {
                throw new InvalidOperationException($"duplicate request id {id} — Interlocked.Increment overflow?");
            }
            return (id, tcs);
        }

        /// <summary>
        /// Deliver a shim completion callback to whichever <see cref="TaskCompletionSource{T}"/>
        /// registered <paramref name="reqId"/>. If <paramref name="errorJson"/> is non-null the
        /// TCS is completed with a mapped <see cref="EngagementCloudException"/>; otherwise the
        /// TCS resolves with <paramref name="resultJson"/> (which may itself be <c>null</c>).
        /// Unknown ids are logged and dropped — that's a shim bug, not a user error.
        /// </summary>
        public static void Resolve(int reqId, string resultJson, string errorJson)
        {
            if (!s_pending.TryRemove(reqId, out var tcs))
            {
                UnityEngine.Debug.LogWarning($"[EngagementCloud] unknown request id {reqId} — completion dropped");
                return;
            }

            if (errorJson != null)
            {
                tcs.SetException(EngagementCloudException.FromJson(errorJson));
            }
            else
            {
                tcs.SetResult(resultJson);
            }
        }
    }
}

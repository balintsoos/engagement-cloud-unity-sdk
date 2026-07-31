using System;
using System.Collections.Concurrent;
using UnityEngine;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Hidden singleton MonoBehaviour that drains a queue of <see cref="Action"/>s on Unity's
    /// main thread each frame. Instantiated once via <see cref="Bootstrap"/> before the first
    /// scene loads and marked <see cref="Object.DontDestroyOnLoad(Object)"/>.
    ///
    /// Every P/Invoke callback (`OnCompletion`, `OnEvent`, `OnLog`) posts to this pump so
    /// downstream consumers — <c>TaskCompletionSource</c> continuations, <c>EventReceived</c>
    /// multicasts, <c>Debug.Log</c> calls — always run on the same thread that owns Unity's API
    /// surface. Backing storage is <see cref="ConcurrentQueue{T}"/> so <see cref="Post"/> is
    /// lock-free from any thread.
    /// </summary>
    [DefaultExecutionOrder(-10000)]
    internal sealed class MainThreadPump : MonoBehaviour
    {
        private static MainThreadPump s_instance;
        private static readonly ConcurrentQueue<Action> s_queue = new ConcurrentQueue<Action>();

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void Bootstrap()
        {
            if (s_instance != null) return;
            var go = new GameObject("[EngagementCloud.MainThreadPump]")
            {
                hideFlags = HideFlags.HideAndDontSave
            };
            DontDestroyOnLoad(go);
            s_instance = go.AddComponent<MainThreadPump>();
        }

        /// <summary>Queue <paramref name="work"/> for the next Update tick on Unity's main thread.</summary>
        public static void Post(Action work)
        {
            if (work == null) return;
            s_queue.Enqueue(work);
        }

        private void Update()
        {
            // Drain everything queued at the top of the frame. Anything enqueued inside a
            // handler runs next frame — prevents unbounded loops when a handler re-posts.
            int drained = 0;
            while (s_queue.TryDequeue(out var work))
            {
                try
                {
                    work();
                }
                catch (Exception ex)
                {
                    Debug.LogException(ex);
                }
                if (++drained >= 256)
                {
                    // Guard against a runaway producer. Anything left will be picked up next frame.
                    break;
                }
            }
        }
    }
}

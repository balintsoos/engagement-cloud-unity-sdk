using System;
using System.Collections.Concurrent;
using UnityEngine;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Hidden MonoBehaviour that drains a <see cref="ConcurrentQueue{Action}"/>
    /// on Unity's main thread every frame. Native completion callbacks from
    /// the shim arrive on arbitrary threads; they enqueue their work here so
    /// <see cref="TaskCompletionSource{TResult}.SetResult"/> continuations
    /// resume on Unity's main thread, safe to touch Unity API from.
    ///
    /// Instantiated once via <see cref="Bootstrap"/>
    /// (<c>[RuntimeInitializeOnLoadMethod(BeforeSceneLoad)]</c>) and marked
    /// <see cref="Object.DontDestroyOnLoad"/>. Not intended to be user-facing.
    /// </summary>
    internal sealed class MainThreadPump : MonoBehaviour
    {
        private static readonly ConcurrentQueue<Action> s_queue = new ConcurrentQueue<Action>();
        private static MainThreadPump s_instance;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        internal static void Bootstrap()
        {
            if (s_instance != null) return;
            var go = new GameObject("[EngagementCloud.MainThreadPump]") { hideFlags = HideFlags.HideAndDontSave };
            s_instance = go.AddComponent<MainThreadPump>();
            DontDestroyOnLoad(go);
        }

        /// <summary>Enqueue an action from any thread. Runs on the next
        /// Unity frame.</summary>
        internal static void Post(Action action)
        {
            if (action == null) return;
            s_queue.Enqueue(action);
        }

        private void Update()
        {
            while (s_queue.TryDequeue(out var action))
            {
                try { action(); }
                catch (Exception e) { Debug.LogException(e); }
            }
        }
    }
}

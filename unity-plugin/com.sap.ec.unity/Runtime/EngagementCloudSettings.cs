using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// User-authored settings asset consumed by <see cref="AutoInit"/>. Load it as
    /// <c>Resources.Load&lt;EngagementCloudSettings&gt;("EngagementCloudSettings")</c> — the
    /// editor menu (<c>Assets/Create/SAP Engagement Cloud/Settings</c>) creates the asset in
    /// the right place with the right filename.
    /// </summary>
    [CreateAssetMenu(
        menuName = "SAP Engagement Cloud/Settings",
        fileName = "EngagementCloudSettings",
        order = 0)]
    public sealed class EngagementCloudSettings : ScriptableObject
    {
        [Tooltip("Application code issued by the Engagement Cloud dashboard (e.g. EMSE3-B4341).")]
        public string applicationCode = "";

        [Tooltip("Call EngagementCloud.Setup() automatically before the first scene loads.")]
        public bool autoInit = true;

        [Tooltip("If set and autoInit is true, LinkContact() is called with this value right after Setup().")]
        public string initialContactValue = "";
    }
}

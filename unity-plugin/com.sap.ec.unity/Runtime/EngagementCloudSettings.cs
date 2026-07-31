using System;
using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// ScriptableObject holding the SDK's initialization parameters. Drop
    /// a single instance into <c>Assets/Resources/</c> (Unity menu:
    /// <c>Assets → Create → SAP Engagement Cloud → Settings</c>) so
    /// <see cref="AutoInit"/> can find it at startup.
    /// </summary>
    [CreateAssetMenu(
        fileName = "EngagementCloudSettings",
        menuName = "SAP Engagement Cloud/Settings",
        order = 100)]
    public sealed class EngagementCloudSettings : ScriptableObject
    {
        [Tooltip("Application code issued by SAP Engagement Cloud. Required.")]
        [SerializeField] private string _applicationCode = "";

        [Tooltip("If true, EngagementCloud.Setup() is invoked automatically on BeforeSceneLoad.")]
        [SerializeField] private bool _autoInit = true;

        public string ApplicationCode => _applicationCode;
        public bool AutoInit => _autoInit;

        /// <summary>Well-known path under which <see cref="AutoInit"/> looks
        /// for the singleton settings asset. Must live in a <c>Resources</c>
        /// folder so <see cref="Resources.Load"/> can find it.</summary>
        public const string ResourcesPath = "EngagementCloudSettings";
    }
}

using UnityEditor;
using UnityEngine;

namespace EngagementCloud.Editor
{
    /// <summary>
    /// Convenience menu item that creates <see cref="EngagementCloudSettings"/> under
    /// <c>Assets/Resources/</c> with the exact file name <see cref="AutoInit"/> looks for. Users
    /// can also use <c>Assets/Create/SAP Engagement Cloud/Settings</c> (declared via
    /// <c>[CreateAssetMenu]</c>) — this shortcut just guarantees the Resources placement.
    /// </summary>
    internal static class SettingsMenuItem
    {
        private const string Menu = "Tools/SAP Engagement Cloud/Create Settings Asset";
        private const string ResourcesDir = "Assets/Resources";
        private const string AssetPath    = "Assets/Resources/EngagementCloudSettings.asset";

        [MenuItem(Menu)]
        private static void CreateAsset()
        {
            if (!AssetDatabase.IsValidFolder(ResourcesDir))
            {
                AssetDatabase.CreateFolder("Assets", "Resources");
            }
            if (AssetDatabase.LoadAssetAtPath<EngagementCloudSettings>(AssetPath) != null)
            {
                EditorUtility.DisplayDialog("Engagement Cloud",
                    $"Settings asset already exists at {AssetPath}", "OK");
                Selection.activeObject = AssetDatabase.LoadAssetAtPath<Object>(AssetPath);
                return;
            }
            var asset = ScriptableObject.CreateInstance<EngagementCloudSettings>();
            AssetDatabase.CreateAsset(asset, AssetPath);
            AssetDatabase.SaveAssets();
            Selection.activeObject = asset;
        }
    }
}

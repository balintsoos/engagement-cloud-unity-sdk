using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace EngagementCloudSamples.Editor
{
    /// <summary>
    /// Editor helpers that materialise our two demo scenes with a real <c>.unity</c> file each.
    /// We build them programmatically instead of committing hand-authored YAML because
    /// scene files embed asset GUIDs that aren't portable across fresh checkouts — letting
    /// Unity assign the GUIDs at scene-creation time makes the resulting scene self-consistent.
    /// </summary>
    public static class SampleSceneBootstrap
    {
        // -- Full sample: mirrors macOS AppKit sample (buttons for every campaign trigger, log panel, etc.).
        [MenuItem("Tools/SAP Engagement Cloud/Create Sample Scene")]
        private static void CreateFullSample()
        {
            var scene = FreshScene();
            AddController<SampleAppController>(scene, name: "SampleAppController");
            SaveScene(scene, "Assets/Scenes/SampleScene.unity",
                message: "Press Play. Setup / Enable / Link, IA1–IA7 triggers, inline slot, log — the whole macOS-sample equivalent.");
        }

        // -- Minimal inline demo: one big RawImage, one status label, one enable button.
        [MenuItem("Tools/SAP Engagement Cloud/Create Inline Demo Scene")]
        private static void CreateInlineDemo()
        {
            var scene = FreshScene();
            AddController<InlineDemoController>(scene, name: "InlineDemoController");
            SaveScene(scene, "Assets/Scenes/InlineDemoScene.unity",
                message: "Press Play. If the SDK is already enabled (typical if you've run the macOS sample), the inline 'ia' message loads on its own. Otherwise click Enable & Load.");
        }

        // ------------------------------------------------------------------ helpers

        private static UnityEngine.SceneManagement.Scene FreshScene()
        {
            EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo();
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            var cameraGo = new GameObject("Main Camera");
            var camera = cameraGo.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.08f, 0.08f, 0.10f);
            cameraGo.tag = "MainCamera";
            SceneManager.MoveGameObjectToScene(cameraGo, scene);

            // UGUI pointer events need an EventSystem in the scene.
            var esGo = new GameObject("EventSystem",
                typeof(UnityEngine.EventSystems.EventSystem),
                typeof(UnityEngine.EventSystems.StandaloneInputModule));
            SceneManager.MoveGameObjectToScene(esGo, scene);

            return scene;
        }

        private static void AddController<T>(UnityEngine.SceneManagement.Scene scene, string name)
            where T : MonoBehaviour
        {
            var go = new GameObject(name);
            go.AddComponent<T>();
            SceneManager.MoveGameObjectToScene(go, scene);
        }

        private static void SaveScene(UnityEngine.SceneManagement.Scene scene, string path, string message)
        {
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
            EditorSceneManager.SaveScene(scene, path);
            AssetDatabase.Refresh();
            EditorUtility.DisplayDialog("Engagement Cloud", $"Created {path}. {message}", "OK");
        }
    }
}

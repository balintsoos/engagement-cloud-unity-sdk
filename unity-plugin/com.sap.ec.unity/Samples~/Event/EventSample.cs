using System.Threading.Tasks;
using EngagementCloud;
using UnityEngine;
using UnityEngine.UI;

namespace EngagementCloudSamples
{
    /// <summary>
    /// Drop this on an empty GameObject and wire an event-name InputField + 6 preset buttons
    /// to fire the campaign triggers the Android e2e test-app defines. Each button posts one
    /// custom event and waits for the in-app overlay to render (the default macOS presenter
    /// pops a borderless NSWindow above the Unity Player).
    /// </summary>
    public sealed class EventSample : MonoBehaviour
    {
        [Tooltip("Custom event name typed by the user (overrides preset buttons).")]
        public InputField eventNameField;

        public Button trackCustomButton;
        public Button trackMysy2Button;   // IA1
        public Button trackMysy3Button;   // Open SAP + AppEvent hello_mobile
        public Button trackMysy4Button;   // no-campaign smoke
        public Button trackViewEventButton;  // IA4
        public Button trackClickEventButton; // IA5
        public Text   statusText;

        private void Start()
        {
            if (trackCustomButton     != null) trackCustomButton.onClick.AddListener(async () => await TrackCustom());
            if (trackMysy2Button      != null) trackMysy2Button.onClick.AddListener(async () => await Track("mysy2"));
            if (trackMysy3Button      != null) trackMysy3Button.onClick.AddListener(async () => await Track("mysy3"));
            if (trackMysy4Button      != null) trackMysy4Button.onClick.AddListener(async () => await Track("mysy4"));
            if (trackViewEventButton  != null) trackViewEventButton.onClick.AddListener(async () => await Track("test_inapp_view_event"));
            if (trackClickEventButton != null) trackClickEventButton.onClick.AddListener(async () => await Track("test_inapp_click_event"));
        }

        private async Task TrackCustom()
        {
            string name = eventNameField != null ? eventNameField.text : "";
            if (string.IsNullOrEmpty(name))
            {
                Status("event name is empty");
                return;
            }
            await Track(name);
        }

        private async Task Track(string eventName)
        {
            try
            {
                Status($"tracking '{eventName}'…");
                await EngagementCloud.EngagementCloud.TrackEvent(eventName);
                Status($"tracked '{eventName}' — overlay should appear if a campaign is configured");
            }
            catch (EngagementCloudException ex)
            {
                Status($"track failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private void Status(string s)
        {
            Debug.Log($"[EventSample] {s}");
            if (statusText != null) statusText.text = s;
        }
    }
}

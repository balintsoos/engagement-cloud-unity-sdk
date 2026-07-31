using System.Threading.Tasks;
using EngagementCloud;
using UnityEngine;
using UnityEngine.UI;

namespace EngagementCloudSamples
{
    /// <summary>
    /// Drop this on an empty GameObject in a scene. Wire the 3 Button fields in the inspector
    /// and click through Enable → Link → Track at runtime; the status Text updates from every
    /// completion, and SDK events flow through EventReceived to the log.
    /// </summary>
    public sealed class SetupSample : MonoBehaviour
    {
        [Tooltip("Application code (matches the iosApp / macosApp Constants.APPLICATION_CODE).")]
        public string applicationCode = "EMSE3-B4341";

        [Tooltip("Contact email (matches the iosApp / macosApp Constants.CONTACT_EMAIL).")]
        public string contactValue = "test1@test.com";

        [Tooltip("Custom event name that triggers an in-app campaign on the backend.")]
        public string eventName = "mysy2";

        public Button enableButton;
        public Button linkButton;
        public Button trackButton;
        public Text   statusText;

        private void OnEnable()
        {
            EngagementCloud.EngagementCloud.EventReceived += OnSdkEvent;
        }

        private void OnDisable()
        {
            EngagementCloud.EngagementCloud.EventReceived -= OnSdkEvent;
        }

        private async void Start()
        {
            bool enabled = false;
            try { enabled = await EngagementCloud.EngagementCloud.IsEnabled(); } catch { /* shim may be absent in Editor */ }
            SetStatus($"Ready. isEnabled={enabled}");
            if (enableButton != null) enableButton.onClick.AddListener(async () => await OnEnableClick());
            if (linkButton   != null) linkButton.onClick.AddListener(async () => await OnLinkClick());
            if (trackButton  != null) trackButton.onClick.AddListener(async () => await OnTrackClick());
        }

        private async Task OnEnableClick()
        {
            try
            {
                SetStatus($"Enabling {applicationCode}…");
                await EngagementCloud.EngagementCloud.Setup(applicationCode);
                SetStatus("Enabled.");
            }
            catch (SdkAlreadyEnabledException)
            {
                SetStatus("Already enabled (persisted from previous run).");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Enable failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private async Task OnLinkClick()
        {
            try
            {
                SetStatus($"Linking {contactValue}…");
                await EngagementCloud.EngagementCloud.LinkContact(contactValue);
                SetStatus($"Linked {contactValue}.");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Link failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private async Task OnTrackClick()
        {
            try
            {
                SetStatus($"Tracking '{eventName}'…");
                await EngagementCloud.EngagementCloud.TrackEvent(eventName);
                SetStatus($"Tracked '{eventName}'.");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Track failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private void OnSdkEvent(SdkEvent evt)
        {
            switch (evt)
            {
                case SdkEvent.AppEvent ae:
                    Debug.Log($"[SetupSample] AppEvent name={ae.Name} payload={ae.PayloadJson}");
                    break;
                case SdkEvent.BadgeCountEvent bc:
                    Debug.Log($"[SetupSample] BadgeCount={bc.BadgeCount} method={bc.Method}");
                    break;
                default:
                    Debug.Log($"[SetupSample] event type={evt.Type}");
                    break;
            }
        }

        private void SetStatus(string message)
        {
            Debug.Log($"[SetupSample] {message}");
            if (statusText != null) statusText.text = message;
        }
    }
}

using System.Threading.Tasks;
using EngagementCloud;
using UnityEngine;

/// <summary>Minimal sample: link and unlink a contact.</summary>
public class ContactSample : MonoBehaviour
{
    [SerializeField] private string _contactFieldValue = "user@example.com";

    private async void Start()
    {
        try
        {
            await EngagementCloud.ContactLink(_contactFieldValue);
            Debug.Log($"[ContactSample] Linked contact: {_contactFieldValue}");
        }
        catch (EngagementCloudException e)
        {
            Debug.LogError($"[ContactSample] Link failed ({e.Type}): {e.Message}");
        }
    }
}

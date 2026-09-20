import os
import sys
import time
import jwt
import requests
import json

KEY_ID = "57KJUL9QCF"
ISSUER_ID = "9c3eebe4-f6c7-4595-a8da-b635b93ab383"
PRIVATE_KEY_PATH = "/Users/command/.appstoreconnect/private_keys/AuthKey_57KJUL9QCF.p8"

with open(PRIVATE_KEY_PATH, 'r') as f:
    private_key = f.read()

def get_token():
    payload = {
        "iss": ISSUER_ID,
        "iat": int(time.time()),
        "exp": int(time.time()) + 1200,
        "aud": "appstoreconnect-v1"
    }
    headers = {
        "alg": "ES256",
        "kid": KEY_ID,
        "typ": "JWT"
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)

token = get_token()
headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

VERSION_ID = "04153a26-b721-42b5-bc94-b50fa607a80a"
LOCALIZATION_ID = "e854f808-3032-4437-9d20-7c7ad3248d98"

print("Patching whatsNew...")
patch_url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/{LOCALIZATION_ID}"
patch_data = {
    "data": {
        "id": LOCALIZATION_ID,
        "type": "appStoreVersionLocalizations",
        "attributes": {
            "whatsNew": "Bug fixes and performance improvements."
        }
    }
}
r_patch = requests.patch(patch_url, headers=headers, json=patch_data)
if r_patch.status_code not in [200, 204]:
    print("Failed to patch whatsNew:", r_patch.text)
    sys.exit(1)

print("Now adding to review submission...")
submission_id = "144de1bc-8c85-48ca-86f7-b8d17432c6b0"
item_url = "https://api.appstoreconnect.apple.com/v1/reviewSubmissionItems"
item_data = {
    "data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {
                "data": {
                    "type": "reviewSubmissions",
                    "id": submission_id
                }
            },
            "appStoreVersion": {
                "data": {
                    "type": "appStoreVersions",
                    "id": VERSION_ID
                }
            }
        }
    }
}
r2 = requests.post(item_url, headers=headers, json=item_data)
if r2.status_code != 201:
    print("Failed to add item:", r2.text)

print("Submitting the reviewSubmission...")
submit_url = f"https://api.appstoreconnect.apple.com/v1/reviewSubmissions/{submission_id}"
submit_data = {
    "data": {
        "id": submission_id,
        "type": "reviewSubmissions",
        "attributes": {
            "submitted": True
        }
    }
}
r3 = requests.patch(submit_url, headers=headers, json=submit_data)
if r3.status_code not in [200, 204]:
    print("Failed to submit:", r3.text)
    sys.exit(1)

print("Successfully submitted for review!")

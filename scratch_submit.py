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

APP_ID = "6753361981"
NEW_VERSION_STRING = "2.6.1"
BUILD_ID = "8945ce35-59b1-46d4-b258-40ae7a492906"

# 1. Check if there's a PREPARE_FOR_SUBMISSION version
url = f"https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION&filter[platform]=IOS"
r = requests.get(url, headers=headers)
data = r.json()

version_id = None
if 'data' in data and len(data['data']) > 0:
    version_id = data['data'][0]['id']
    print(f"Found existing PREPARE_FOR_SUBMISSION version: {version_id}")
    # Update it to 2.6.1 if needed
    patch_url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{version_id}"
    patch_data = {
        "data": {
            "id": version_id,
            "type": "appStoreVersions",
            "attributes": {
                "versionString": NEW_VERSION_STRING
            }
        }
    }
    r2 = requests.patch(patch_url, headers=headers, json=patch_data)
    print("Patch version string response:", r2.status_code)
else:
    # Create new version
    print(f"Creating new version {NEW_VERSION_STRING}")
    create_url = "https://api.appstoreconnect.apple.com/v1/appStoreVersions"
    create_data = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": NEW_VERSION_STRING
            },
            "relationships": {
                "app": {
                    "data": {
                        "type": "apps",
                        "id": APP_ID
                    }
                }
            }
        }
    }
    r_create = requests.post(create_url, headers=headers, json=create_data)
    if r_create.status_code != 201:
        print("Failed to create version:", r_create.text)
        sys.exit(1)
    version_id = r_create.json()['data']['id']
    print(f"Created version: {version_id}")

# 2. Attach build to version
print(f"Attaching build {BUILD_ID} to version {version_id}")
attach_url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{version_id}/relationships/build"
attach_data = {
    "data": {
        "type": "builds",
        "id": BUILD_ID
    }
}
r_attach = requests.patch(attach_url, headers=headers, json=attach_data)
if r_attach.status_code not in [200, 204]:
    print("Failed to attach build:", r_attach.text)
    sys.exit(1)

print("Build attached successfully.")

# 3. Submit for review
print(f"Submitting version {version_id} for review...")
submit_url = "https://api.appstoreconnect.apple.com/v1/appStoreVersionSubmissions"
submit_data = {
    "data": {
        "type": "appStoreVersionSubmissions",
        "relationships": {
            "appStoreVersion": {
                "data": {
                    "type": "appStoreVersions",
                    "id": version_id
                }
            }
        }
    }
}
r_submit = requests.post(submit_url, headers=headers, json=submit_data)
if r_submit.status_code != 201:
    print("Failed to submit for review:", r_submit.text)
    sys.exit(1)

print("Successfully submitted for review!")

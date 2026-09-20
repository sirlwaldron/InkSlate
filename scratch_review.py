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
VERSION_ID = "04153a26-b721-42b5-bc94-b50fa607a80a"

print("1. Creating reviewSubmission...")
create_url = "https://api.appstoreconnect.apple.com/v1/reviewSubmissions"
create_data = {
    "data": {
        "type": "reviewSubmissions",
        "attributes": {
            "platform": "IOS"
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
r1 = requests.post(create_url, headers=headers, json=create_data)
if r1.status_code != 201:
    print("Failed to create reviewSubmission:", r1.text)
    # Check if there is already an active one
    print("Checking for existing review submission...")
    r1_get = requests.get(f"https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}/reviewSubmissions?filter[state]=READY_FOR_REVIEW", headers=headers)
    items = r1_get.json().get("data", [])
    if not items:
        sys.exit(1)
    submission_id = items[0]["id"]
else:
    submission_id = r1.json()["data"]["id"]

print(f"Submission ID: {submission_id}")

print("2. Adding appStoreVersion to reviewSubmissionItems...")
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
    # Could already be added, let's ignore for a moment

print("3. Submitting the reviewSubmission...")
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

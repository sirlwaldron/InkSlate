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

BUILD_ID = "8945ce35-59b1-46d4-b258-40ae7a492906"

# Check if build is missing export compliance
build_url = f"https://api.appstoreconnect.apple.com/v1/builds/{BUILD_ID}"
r = requests.get(build_url, headers=headers)
print(json.dumps(r.json(), indent=2))

patch_url = f"https://api.appstoreconnect.apple.com/v1/builds/{BUILD_ID}"
patch_data = {
    "data": {
        "id": BUILD_ID,
        "type": "builds",
        "attributes": {
            "usesNonExemptEncryption": False
        }
    }
}
r2 = requests.patch(patch_url, headers=headers, json=patch_data)
print("Patch export compliance response:", r2.status_code)
if r2.status_code not in [200, 204]:
    print(r2.text)


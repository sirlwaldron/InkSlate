# App Store Submission Checklist

Use this before submitting InkSlate to the App Store.

## 1. Privacy Policy & Terms

Privacy policy and terms are in `docs/` and point to GitHub Pages:
- **Privacy:** https://sirlwaldron.github.io/InkSlate/privacy.html
- **Terms:** https://sirlwaldron.github.io/InkSlate/terms.html

1. **Enable GitHub Pages** in your repo (Settings → Pages → Deploy from branch, main, /docs).

2. **Add the privacy policy URL** in App Store Connect → App Privacy / App Information.

## 2. Privacy Manifest

`InkSlate/PrivacyInfo.xcprivacy` is included. Ensure it’s in the target:

- In Xcode, select the InkSlate target → Build Phases
- Under "Copy Bundle Resources", add `PrivacyInfo.xcprivacy` if it’s missing
- With file system sync, it should be included automatically

## 3. Screenshots

Capture screenshots for:

- **6.7" iPhone** (iPhone 15 Pro Max, 14 Pro Max)
- **6.5" iPhone** (iPhone 11 Pro Max, XS Max)
- **5.5" iPhone** (iPhone 8 Plus)

**Steps:**
1. Run the app in Simulator (e.g., iPhone 15 Pro Max)
2. Navigate to key screens (Notes, Journal, Recipes, etc.)
3. `Cmd + S` to save the screenshot, or `Cmd + Shift + 5` to capture
4. Upload to App Store Connect under the correct size bucket

**Suggested screens:**
- Notes list with a note open
- Journal with streak and entries
- Recipes or Want to Watch
- Main menu / home

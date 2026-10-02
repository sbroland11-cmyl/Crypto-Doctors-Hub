# CDH — Google Drive + Spark Backend Setup

This project removes the Flutter dependency on Firebase Cloud Storage. Media is stored in Google Drive through a Google Apps Script backend. Firestore remains the database/entitlement store.

## 1. Create the Drive folder

Create one dedicated Google Drive folder for CDH media, for example:

CDH APP STORAGE
- payment_proofs (created automatically)
- mentorship_chat (created automatically)
- mentorship_content (created automatically)

Copy the folder ID from the Drive URL.

## 2. Create the Apps Script

Create a new Google Apps Script project using the CDH Google account.
Copy `google_apps_script_Code.gs` into `Code.gs` and `google_apps_script_appsscript.json` into the Apps Script manifest.

Set these Script Properties:

- `CDH_FIREBASE_WEB_API_KEY` = the Firebase Web API key from `lib/firebase_options.dart`
- `CDH_DRIVE_ROOT_FOLDER_ID` = the dedicated CDH Drive folder ID
- `CDH_PROXY_SECRET` = a long random secret (reserved for future signed media endpoints)
- `CDH_TRONGRID_API_KEY` = optional/current TRON API key
- `CDH_ETHERSCAN_API_KEY` = Etherscan API key used for Ethereum/BSC token-transfer verification

The Drive backend validates the Firebase ID token before allowing a user-scoped upload/download.

## 3. Deploy as Web App

Deploy -> New deployment -> Web app.

Execute as: Me / User deploying the script.
Who has access: Anyone.

Copy the `/exec` deployment URL.

## 4. Build CDH with the backend URL

Use:

`flutter build apk --dart-define=CDH_DRIVE_BACKEND_URL=<YOUR_APPS_SCRIPT_EXEC_URL>`

The same define is required for web/debug runs that use Drive or automatic crypto payments.

## 5. Automatic crypto payments

Automatic payment supports:

- USDT TRC20
- USDT BEP20
- USDT ERC20

The backend creates a unique USDT amount for each order, records the order in Firestore, and does not trust the Flutter client to grant entitlements.

The user then submits the blockchain transaction hash. The backend verifies destination + network + USDT transfer + exact amount before granting Premium/Mentorship entitlements.

Easypaisa remains manual because there is no bank API integration in the CDH baseline.

## 6. Important security rule

Do not place Google Drive credentials, refresh tokens, service-account private keys, or Apps Script owner credentials inside Flutter.

## 7. Current bridge upload limit

The Apps Script bridge intentionally caps one upload at 45 MB. This protects Apps Script execution/memory limits. Larger mentorship video delivery should use a resumable Drive bridge in a later hardening pass rather than silently increasing the limit.

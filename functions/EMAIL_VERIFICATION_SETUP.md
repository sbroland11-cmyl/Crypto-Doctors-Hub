# CDH Email-Code Verification Setup

The Flutter app now uses Firebase callable functions for both signup and login email-code verification. The verification code is generated and checked on the server. The code is never stored in Flutter or returned to the app.

## 1. Install function dependencies

From the Firebase project root:

```bash
cd functions
npm install
```

## 2. Configure SMTP secrets

The functions require these Firebase Secret Manager values:

```bash
firebase functions:secrets:set CDH_SMTP_HOST
firebase functions:secrets:set CDH_SMTP_PORT
firebase functions:secrets:set CDH_SMTP_USER
firebase functions:secrets:set CDH_SMTP_PASS
firebase functions:secrets:set CDH_SMTP_FROM
firebase functions:secrets:set CDH_EMAIL_CODE_PEPPER
```

For Gmail/Google Workspace SMTP, typical values are:

- `CDH_SMTP_HOST` = `smtp.gmail.com`
- `CDH_SMTP_PORT` = `587`
- `CDH_SMTP_USER` = the sender Gmail/Workspace address
- `CDH_SMTP_PASS` = an SMTP-capable app password for that sender account (do not use the normal Gmail password)
- `CDH_SMTP_FROM` = the sender address
- `CDH_EMAIL_CODE_PEPPER` = a long random secret used only for hashing verification codes

The destination Gmail address is supplied by the user at runtime.

## 3. Deploy the authentication functions

From the Firebase project root:

```bash
firebase deploy --only functions:startSignupEmailCode,functions:verifySignupEmailCode,functions:finalizeSignupEmailVerification,functions:startLoginEmailCode,functions:verifyLoginEmailCode
```

## 4. Flutter dependency

The app now requires:

```yaml
cloud_functions: ^6.5.0
```

Run:

```bash
flutter pub get
```

## 5. What the deployed flow does

### Signup

Email -> server checks that it is not already registered -> server generates a one-time code -> SMTP sends it -> user enters code -> server verifies it -> Flutter creates the Firebase password account -> server marks the Firebase Auth email as verified.

### Login

Email -> server checks that the account exists -> server generates a one-time code -> SMTP sends it -> user enters code -> server verifies it -> Firebase custom token is issued -> Flutter signs in with that token.

Codes expire after 10 minutes, are single-use, and are limited to five failed verification attempts. Code requests are rate-limited per email address.

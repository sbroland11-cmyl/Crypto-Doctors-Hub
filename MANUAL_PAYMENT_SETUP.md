# CDH Payment System — Spark + Google Drive Architecture

The CDH payment layer now uses a hybrid architecture designed to avoid Firebase Cloud Storage and Firebase Cloud Functions.

## Automatic crypto payments

Supported:
- USDT TRC20
- USDT BEP20
- USDT ERC20

Flow:
1. User selects Premium or Mentorship.
2. User selects a USDT network.
3. Google Apps Script backend validates the Firebase user.
4. Backend reads the authoritative plan and receiving wallet from `paymentSettings/config`.
5. Backend creates a unique USDT amount and stores `paymentOrders/{orderId}`.
6. User pays the exact amount to the configured wallet.
7. User submits the transaction hash, or the scheduled backend scanner detects the matching transfer.
8. Backend verifies destination, network, USDT contract/token and exact amount.
9. Backend writes `paymentTransactions/{transactionId}` and changes the order to `paid`.
10. Backend grants the appropriate Premium/Mentorship entitlement and creates CDH Mail/badge records.

The Flutter client never writes Premium/Mentorship entitlements.

## Easypaisa

Easypaisa remains a manual payment path because the baseline does not contain a bank/payment-provider API integration. Its proof screenshot is stored in Google Drive rather than Firebase Storage and the Admin continues to approve/reject it.

## Media storage

Firebase Storage is no longer used by the Flutter project.

Google Drive stores:
- payment proofs
- mentorship chat screenshots
- mentorship PDFs/images/videos uploaded through the Drive bridge

Firestore stores only metadata/references and authorization state.

## Spark requirement

Do not deploy the legacy `functions/` directory if the Firebase project must remain on Spark. The replacement backend is `google_apps_script/`.

See `GOOGLE_DRIVE_SPARK_SETUP.md` for deployment and Script Property configuration.

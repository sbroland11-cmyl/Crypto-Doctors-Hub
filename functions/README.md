# Legacy Firebase Functions — NOT USED by the Spark CDH architecture

The current CDH Spark architecture uses `google_apps_script/` instead of Firebase Cloud Functions.

Do not deploy this folder if the Firebase project must remain on the Spark plan. It is retained only so previously completed backend source is not silently discarded.

Active replacement:
- Google Drive media bridge: `google_apps_script/Code.gs`
- Automatic payment order/scanner backend: `google_apps_script/Code.gs`

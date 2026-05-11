# Production Notifications

Food App push notifications need both backend/APNs configuration and an iOS
distribution profile with Push Notifications enabled.

## Apple Developer

1. Open the App ID for `com.shantanu.foodapp`.
2. Enable **Push Notifications**.
3. Regenerate/download the production provisioning profile used for TestFlight.
4. Create or reuse an APNs Auth Key (`.p8`) and note:
   - Team ID
   - Key ID
   - Bundle ID: `com.shantanu.foodapp`

The app entitlements use `$(APS_ENVIRONMENT)`: Debug is `development`, Release
is `production`.

## Render Environment

Set these on the backend service:

```dotenv
NOTIFICATION_RUNNER_ENABLED=true
NOTIFICATION_RUNNER_INTERVAL_MS=300000
APNS_ENABLED=true
APNS_ENVIRONMENT=production
APNS_TEAM_ID=...
APNS_KEY_ID=...
APNS_BUNDLE_ID=com.shantanu.foodapp
APNS_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----
```

`render.yaml` already declares the non-secret defaults and marks secret values
as `sync: false`.

## Deploy Order

1. Deploy backend. Render runs `npm run migrate && npm run start`, so
   `0023_notification_system.sql` applies before startup.
2. Confirm `/health` is OK.
3. Open the testing dashboard `Notifications` tab.
4. Run a manual sweep. A correctly configured system should return a summary
   instead of APNs configuration errors.
5. Build/upload TestFlight with the regenerated push-enabled profile.

## Safety

`npm run preflight:release` fails if the notification runner is enabled without
APNs being fully configured.

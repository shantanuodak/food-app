# iOS TestFlight Helper Scripts

## Scripts

1. `check_testflight_release_config.sh`
   - Validates Release config safety gates in `Food App.xcodeproj/project.pbxproj`.
2. `set_release_api_base_url.sh`
   - Updates Release `API_BASE_URL` to the provided HTTPS production endpoint.
3. `bump_build_number.sh`
   - Increments `CURRENT_PROJECT_VERSION` across project/target configs.
4. `testflight_preupload_gate.sh`
   - Runs Release config checks and backend pre-upload gate commands.

## Typical usage order

```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/set_release_api_base_url.sh" "https://<your-prod-api-domain>"
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/testflight_preupload_gate.sh"
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/bump_build_number.sh"
```

# Rosa v2.10.58 — Guest scanner test guide

## Fast local test on the development PC

1. Extract the release ZIP into a new folder (do not overwrite a live production folder).
2. Double-click `START_ROSA.bat` and keep the server window open.
3. Open `http://127.0.0.1:8819` on the same PC and sign in with the demo owner account listed in `README.md`.
4. Open a test reservation. In the guest registration/check-in panel, choose **Send guest check-in link** and copy the generated link.
5. Open that link in a second browser tab on the same PC. Grant camera permission when asked.
6. Test both **Scan now** and **Enable auto-capture** with a synthetic/non-sensitive sample image displayed on another screen or printed on paper. Review every field before confirming.
7. Try a deliberately blurry or poorly lit sample and confirm Rosa asks for a clearer image or manual correction.
8. In the owner tab, open **Review identity verification**. Confirm a guest submission is still pending verification and cannot be treated as identity-verified merely because OCR succeeded.

## Testing on a phone

- `START_ROSA_PHONE.bat` lets the phone reach Rosa over the same trusted Wi-Fi for general UI and manual-entry testing.
- **Camera access normally requires a secure browser context (HTTPS or localhost).** A plain `http://192.168.x.x:8819` LAN URL may load the page but block `getUserMedia`, so a disabled camera on that URL does not necessarily indicate a Rosa scanner bug.
- For actual phone-camera testing, use a trusted HTTPS staging deployment or an HTTPS development tunnel you control. Do not expose a production database or real guest data through a temporary tunnel.

## Privacy and safe test data

- Use synthetic MRZ samples or official specimen documents only; do not upload real passports/IDs into test chats or issue trackers.
- The scanner processes captured pixels locally in the browser. This guide does not change the rule that document images must not be uploaded or persisted.
- OCR/check digits validate text consistency, not document authenticity or the identity of the person holding it.

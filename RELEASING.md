# Publishing

1. Create an empty GitHub repository and upload the contents of the source archive (including `.github` and `.gitignore`), or push this directory using Git.
2. Review the MIT license and the limitations in README before publishing.
3. Run tests and build. `dist/` is ignored by Git; upload application ZIPs as release assets, not source files.
4. For a public user-facing binary, build with `SIGNING_IDENTITY='Developer ID Application: …' python3 Scripts/build.py`, then use Apple's `notarytool` and `stapler`. After stapling, recreate the ZIP and its SHA-256. No certificates, passwords or API credentials belong in Git.
5. Without a Developer ID certificate, describe binaries clearly as ad-hoc signed and not notarized. Source builds remain available; do not claim frictionless Gatekeeper approval.
6. Use a pre-release until Intel hardware and the intended OS versions pass manual checks. Test on a spare machine: both modes, battery/AC transitions, idle sleep, lid close, wake, cancel authorization, move the running app, and quit/relaunch. Record actual results without treating architecture compilation as hardware validation.

No repository, release, or remote upload is created by the packaging scripts.

# Per-organization branding (enterprise builds)

Run `scripts\build-wizard.ps1` on a Windows build machine. The form asks for:

| Field | Effect |
|---|---|
| Organization name | Shown in the main window footer and title bar; written to the audit log (`branding` event) |
| Company logo | Normalized to PNG (max 256 px high) and embedded; shown in the footer |
| Concurrent users | Shown as "Up to N concurrent users"; also written to `relay.env` as `RELAY__MaxConcurrentSessions=N` for that organization's relay. 0 = unlimited |
| Developed by | Defaults to `Toolveriq`, shown in the footer |

Output: `branding\<org>\` (branding.json, logo.png, relay.env) and `artifacts\<org>\RemoteTool.exe`. Repeat per customer.
CI / no form: `scripts\build-wizard.ps1 -FromFile branding\acme` or `scripts\publish-app.ps1 -BrandingDir branding\acme`
(MSBuild: `-p:BrandingDir=...` or env `RT_BRANDING_DIR`). Flags: `-NoBuild`, `-SignThumbprint`, `-SkipTests`.

**Seat limit:** the relay is the authority (an exe-side check could be patched out). The exe adds a best-effort pre-check: before connecting through the relay, the viewer asks it for the active session count (new relay messages `Usage`/`UsageReply`, count only) and shows "User limit reached" if the count is at the limit. If the count cannot be read (older relay, wrong key, unreachable) it does not block. Deploy the customer's relay with the generated `relay.env`
(each session = one active remote connection). Name and logo are cosmetic and extractable from the exe.

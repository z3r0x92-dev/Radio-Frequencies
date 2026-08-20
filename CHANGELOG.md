# Radio Frequencies changelog

## 0.11.1

- Fixed Player Request so the selected track is submitted to the station currently open in Listener View.
- Requests no longer fail merely because no powered receiver is detected; actual music playback still requires a tuned receiver.
- Bumped the client/server protocol to reject mixed 0.11.0 and 0.11.1 installations.

## 0.11.0

- Redesigned Listener, Station, and Admin screens to use the same 1180 by 680 Command Center structure as Survivor League.
- Added matching status header, product identity row, aligned navigation tabs, bordered content regions, and consistent footer treatment.
- Unified the Project Zomboid, Meeks Protocol, and Military palettes with their Survivor League equivalents.
- Preserved wrapped two-line broadcast history entries and full selected-announcement details.
- Preserved all existing playback, requests, favorites, queue, DJ, emergency override, and broadcast behavior.
- Bumped the client/server protocol to prevent mixed UI installations.

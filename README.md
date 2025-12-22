# Virtual Link Runner

Batch script for Windows that listens for LLDP, grabs switch port info, and shows you what you're plugged into.

## What it shows
- System Name
- Port Description
- VLAN ID / PVID

## How it works
1. Uses `pktmon` (built into Windows) with a filter for LLDP (`01-80-C2-00-00-0E`).
2. Waits until an LLDP frame is actually seen.
3. Buffers a few seconds of traffic.
4. Stops capture and converts it to text.
5. Parses only **received** LLDP frames, not what your NIC advertises.
6. Prints results in color.

After it prints, press any key to run it again on another jack.

## Requirements
- Windows 10/11
- Local admin (the script will auto-elevate with UAC if needed)

Works with internal NICs, USB Ethernet dongles, docks, etc.

## VLAN mapping
The script includes a `:vlanOutput` section that maps common VLAN IDs to names and warnings.  
Example cases:
- `101` DATA  
- `102` VOICE
- `1`  NATIVE / not configured, escalate  

You can edit this mapping to match your environment.

## License
GPL-3.0  
https://www.gnu.org/licenses/gpl-3.0.html

## Credits
- Author: Dylan C.
- Inspired by: LinkSkippy by @andkrau

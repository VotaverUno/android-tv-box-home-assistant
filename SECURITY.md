# Security Policy

## Scope

This repository contains **documentation and helper scripts** only. It does not ship firmware,
APKs or any credential. The Home Assistant instance you build with these scripts is your own
responsibility.

## Reporting a vulnerability

If you find a security issue in this repository (for example a script that leaks secrets,
an unsafe default, or a command that could damage a device):

1. **Do not open a public issue** with exploit details;
2. Use GitHub's private reporting: repository page → **Security** → **Report a vulnerability**
   (Security Advisories), or contact the maintainer via the email shown on the GitHub profile;
3. Please include: affected file, impact, reproduction steps, suggested fix (if any).

You can expect an initial response within a few days. This is a hobby project — thank you for
your patience.

## What is out of scope

- Vulnerabilities in Home Assistant, Termux, `midea_ac_lan`, `haier`, `bemfa_cloud` — report them
  to the respective projects;
- Issues caused by exposing your instance to the internet instead of using a VPN;
- "Attacks" that require physical access to the box or the LAN.

## Secrets policy (for contributors)

Never commit or paste into issues:

- IP addresses, MAC addresses, serial numbers;
- account names, passwords, tokens, API keys;
- Bemfa UID, Midea/Haier device tokens;
- `~/.homeassistant/.storage/` contents.

If you accidentally publish a secret: **revoke/rotate it first**, then clean the history
(`git filter-repo` / BFG) and force-push. Rotating is more important than hiding.

## Hardening checklist for readers

- Keep SSH (port 8022) and Home Assistant (8123) on the LAN only; use VPN for remote access;
- Do not enable `default_config:` or `recorder:` on a 2 GB box (performance, not security);
- Publish device names in screenshots only if you are comfortable with them;
- Back up before editing system state; use `scripts/stability/rollback.sh` if something breaks.

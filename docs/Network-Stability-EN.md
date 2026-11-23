# Box Disappears from LAN / Services Don't Start After Reboot: Troubleshooting Guide

> Real issue found and fixed in Nov 2026 on a Xiaomi Box 4S Pro (Android 9 / armv7).
> It looks like "HA crashed", but the root cause is usually **Wi-Fi / router** or **boot autostart**,
> not HA code.

## 0. One-minute triage

| Symptom | Most likely cause |
|---|---|
| UI shows "Connection lost, reconnecting"; 8123/8022 unreachable | box lost the network (section 1) |
| Box missing from the router's client list | Wi-Fi disconnected / wrong subnet |
| Box listed on the router, but unreachable | Wi-Fi "fake online" (interface UP, IP present, gateway unreachable) |
| After reboot HA never comes back, manual Termux start fixes it | Termux:Boot did not fire (1.4) |
| After reboot ADB (5555) is gone but SSH works | normal: `adb tcpip` does not survive reboot |

## 1. Root causes (by likelihood)

### 1.1 Multiple gateways / APs with the **same Wi-Fi name** (most common)

Two routers / ONTs (e.g. two China Telecom gateways) broadcast the same SSID and password:
- devices may attach to either one; same name does **not** mean same network;
- if one of them does NAT / runs a second DHCP, or its mesh/bridge uplink is broken,
  the device becomes "fake online";
- the Android TV Wi-Fi state machine does **not** self-heal: `wlan0` is UP with an IP,
  but `ping <gateway>` returns `Destination Host Unreachable`.

**Real output:**
```
$ ping -c 2 192.168.1.1
From 192.168.1.69: icmp_seq=1 Destination Host Unreachable
100% packet loss
$ getprop dhcp.wlan0.gateway     # empty
$ ifconfig wlan0                 # UP, inet 192.168.1.69
```

### 1.2 Stale Wi-Fi configuration on the box

After changing routers/passwords/AP nodes, old settings can leave the box attached "somewhere wrong".
**Fix: forget the network and re-enter the password** (this fixed it in one step in our case).

### 1.3 Double DHCP / double NAT on the same subnet

If both gateways use `192.168.1.1` and both run DHCP, clients get addresses in the same subnet but
different broadcast domains; connectivity becomes flaky.
Check: log in to both gateways; only one should run DHCP.

### 1.4 Termux:Boot did not fire after reboot

- Termux:Boot runs the scripts in `~/.termux/boot/` (ours: `start-ha.sh`, which starts HA and SSH);
- some TV boxes block third-party autostart (and "fast boot/standby" modes do not send BOOT_COMPLETED);
- symptom: 8123/8022 are down after reboot; opening Termux and running `sv up hass` fixes it;
- check `~/boot.log` for a `boot hook fired` line from this boot.

### 1.5 ADB 5555 dies on reboot (expected)

`adb tcpip 5555` is temporary and does not survive reboots. Use **SSH (8022)** for remote maintenance,
and let it start from Termux:Boot.

## 2. Diagnosis from three angles

### On the box (Termux)
```bash
ifconfig wlan0                      # UP / inet IP
ping -c 2 192.168.1.1               # gateway reachable? (key check)
getprop dhcp.wlan0.ipaddress        # DHCP address present?
sv status hass sshd                 # services running?
tail -n 20 ~/boot.log               # did the boot hook run?
```

### On the router
- Client list: find the box MAC (starts with `7C:88:99`), check online state / IP / link type / signal;
- With two gateways: confirm only one runs DHCP and their LAN IPs differ.

### On the PC
```powershell
ipconfig | findstr /i "IPv4"
arp -a | findstr 192.168.1.
```
Make sure the PC and the box are on the same subnet and the gateway is pingable.

## 3. Fixes

### 3.1 Box "fake online" (interface fine, gateway unreachable)
1. Box settings → Network → the Wi-Fi network → **Forget network**;
2. Re-select the SSID, **re-enter the password**;
3. In Termux: `ping -c 2 192.168.1.1` to confirm;
4. Then `sv up hass` (and `sv up sshd`).

> Xiaomi Box path: Settings (gear) → Network & Internet → Wi-Fi → select network → Forget network.

### 3.2 Two gateways with the same SSID
Pick one, ordered by least impact:
1. **Lower the mesh roaming thresholds** (e.g. RSSI -65/-60 → -75/-70) to reduce flapping;
2. Put the second gateway in **wired backhaul / AP mode**, disable its DHCP, set a different LAN IP (e.g. 192.168.1.2);
3. If coverage isn't needed: **turn off the second gateway's Wi-Fi only** (same SSID/password means
   other devices reconnect to the main gateway automatically, no re-provisioning);
4. Do not rename the SSID unless you accept re-provisioning every IoT device.

### 3.3 Services not starting after reboot
1. Manual recovery (one minute):
   ```bash
   cd ~ && bash ~/start-ha-env.sh    # or: sv up hass; sv up sshd
   ```
2. Open **Termux:Boot** once (the white instruction page is normal; it has no settings UI);
3. Look for **Fast boot / Standby / Power** in the box settings and disable "fast boot"
   so a real cold boot happens (only cold boot sends BOOT_COMPLETED);
4. If the firmware has no autostart manager, accept "open Termux once after a power loss".

### 3.4 Long-term stability
- Add a **USB Ethernet adapter** (avoid Wi-Fi roaming / fake-online states);
- Add a **UPS** to avoid power-loss reboots;
- Reserve a DHCP address for the box (if the gateway firmware lacks it, set a static IP in the box Wi-Fi settings).

## 4. Prevention checklist

- [ ] only **one DHCP server** at home;
- [ ] with multiple gateways, distinguish SSIDs or configure mesh/AP properly;
- [ ] on Wi-Fi weirdness, try "forget network → reconnect" before reinstalling HA;
- [ ] remember the two recovery commands: `sv up hass` / `sv up sshd`;
- [ ] after a reboot check `~/boot.log` first: autostart problem or network problem?
- [ ] prefer wired (USB Ethernet adapter) for 24/7 operation.

## 5. TL;DR

> A "disappearing" box is almost always a **Wi-Fi / router** issue (same-SSID multi-gateway,
> fake-online, stale config), not HA code. Services not starting after a reboot is **Termux:Boot
> not firing**; `sv up hass` brings it back. Distinguish the two before changing anything.

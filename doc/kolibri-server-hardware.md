# Kolibri Server: Hardware Purchase List

The parts to build one offline Kolibri server. It creates its own Wi-Fi network so learner phones, tablets and laptops can connect to Kolibri with no internet.

*Prices checked on Amazon on Sept 28, 2026, before tax. Prices and stock change often.*

---

## Parts to buy

| # | Component | Product | Price | Link |
|---|-----------|---------|------:|------|
| 1 | Server | Lenovo ThinkCentre M910q Tiny (Renewed): Intel Core i5-7500T, 16 GB DDR4 RAM, new 512 GB NVMe SSD, Wi-Fi/Bluetooth, wireless keyboard and mouse, Windows 10 Pro | $193.50 | [Amazon B09SWPCND2](https://www.amazon.com/dp/B09SWPCND2) |
| 2 | Wireless adapter | Wisoqu RZ616 **MediaTek MT7922A22M** M.2 Wi-Fi 6E card, tri-band, Bluetooth 5.2, Linux compatible | $25.43 | [Amazon B0DY1V5QWF](https://www.amazon.com/dp/B0DY1V5QWF) |
| 3 | Wi-Fi antenna | Tenmory dual-band 8 dBi RP-SMA antenna kit with MHF4 (U.FL) to RP-SMA extension cables, 2.4 / 5.8 GHz | $8.99 | [Amazon B07QKF18KM](https://www.amazon.com/dp/B07QKF18KM) |
| | | **Total per server** | **$227.92** | |

Short links you shared: [server](https://a.co/d/0bcBbaQA) · [wireless adapter](https://a.co/d/018biZ6x) · [antenna](https://a.co/d/02IRE5Vy)

---

## Why each part

### 1. Server: Lenovo ThinkCentre M910q Tiny

- Small, quiet and low-power, so it can sit in a classroom and run all day.
- **16 GB RAM** is plenty for Kolibri with many learners signed in at once.
- **512 GB NVMe SSD** holds the OS plus several large content channels (Khan Academy and similar channels can take tens of GB each).
- It's a renewed unit that ships with Windows 10 Pro. For the class, plan to wipe it and install **Ubuntu Server 24.04 LTS** or **Debian 12**.
- The wireless keyboard and mouse are useful during setup. After that the server can run without a screen ("headless").

### 2. Wireless adapter: MediaTek MT7922 (RZ616) M.2 card

- Replaces the Wi-Fi card that comes in the M910q's M.2 Wi-Fi slot.
- **Why this chip:** the MT7922 uses the Linux `mt7921e` driver, which supports **access point (AP) mode**. The server can broadcast its own Wi-Fi network with `hostapd` or NetworkManager. Many Intel cards (like the AX210) can't be used as a 5 GHz access point on Linux.
- Needs a recent Linux kernel and the `linux-firmware` package. Ubuntu 24.04 and Debian 12 (with firmware) include both.
- Tri-band Wi-Fi 6E, but for classroom use run the access point on **2.4 GHz or 5 GHz** so older phones and tablets can connect.

### 3. Wi-Fi antenna kit

- The card has two small **MHF4** antenna connectors. This kit includes MHF4-to-RP-SMA cables and two 8 dBi dual-band antennas.
- External antennas give much better range than the small internal antenna, which matters when a whole classroom connects to one server.
- 2.4 / 5 GHz coverage matches the recommended access-point bands.

---

## Before ordering: check these

- [ ] **Antenna exit point.** The M910q Tiny doesn't have a standard RP-SMA hole. Check the rear panel for a knock-out or unused port opening, or plan to drill one or route the cables out through a vent.
- [ ] **Card swap.** Open the case (one rear screw, slide the cover off) and confirm the Wi-Fi slot holds an M.2 2230 card with the stock card removed. Keep the original card as a spare.
- [ ] **Renewed condition.** Confirm the unit arrives with its power adapter, and check the RAM and SSD sizes in the BIOS on first boot.
- [ ] **Stock.** Amazon showed low stock for both the server ("only 1 left") and the MT7922 card ("only 2 left"). If you're buying for more than one site, order early or line up an alternate listing.

---

## Optional items (no links yet)

| Item | Why |
|------|-----|
| USB flash drive, 8 GB or larger | Installer for Ubuntu Server / Debian |
| Ethernet cable | Internet during setup and for downloading Kolibri channels |
| External USB SSD / drive | Copying channels between servers, backups |
| Surge protector or small UPS | Protects the server from power cuts at the site |
| Monitor with HDMI or DisplayPort cable | Only needed for first setup; after that you can manage it over the network |

---

## How the parts fit together

```
 [Learner devices]  ))) Wi-Fi (2.4/5 GHz) )))  [Antennas]
                                                   │ MHF4 cables
                                            [MT7922 M.2 card]
                                                   │
                                   [Lenovo M910q Tiny: Ubuntu Server]
                                     ├─ hostapd / NetworkManager (Wi-Fi access point)
                                     ├─ dnsmasq (hands out IP addresses)
                                     └─ Kolibri server  →  http://<server-ip>:8080
```

Learners join the server's Wi-Fi network, open a browser, go to the server address on port **8080**, and sign in to Kolibri.

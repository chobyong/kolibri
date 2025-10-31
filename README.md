HIM Walled Garden (captive portal)
=================================
 
Overview
--------
 
This document provides a complete guide for setting up an offline educational server using Kolibri. The server will broadcast its own Wi-Fi network and provide a "walled garden" or "captive portal" that directs all users to the educational content without needing an internet connection.
 
### Hardware Requirements
 
- **Server:** Minimum 8GB RAM, 512GB NVMe SSD.
- **Networking:** Must have both an Ethernet port (for initial setup) and a wireless card (to act as the Access Point).
 
---
 
### Part 1: Initial Server Setup
 
This section covers setting up the base operating system.
 
1.  **Install Debian:** Perform a fresh installation of the latest Debian stable release. During installation, ensure the SSH server is enabled and a standard desktop environment is **not** installed to keep the system minimal.
 
2.  **Create User:** Create a standard user named `him`.
 
3.  **Grant Sudo Privileges:** Log in as `root` and add the `him` user to the `sudo` group to allow administrative actions.
 
    ```bash
    usermod -aG sudo him
    ```
 
4.  **Log in as `him`:** Log out from the `root` account and log back in as the `him` user. All subsequent commands should be run as `him` (using `sudo` when required).
 
5.  **Disable Power Saving:** To ensure the server is always available, disable suspend and hibernation modes.
 
    ```bash
    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    ```
 
---
 
### Part 2: Kolibri Installation
 
Next, install the Kolibri educational platform.
 
1.  **Add Kolibri Repository:** Kolibri provides a PPA (Personal Package Archive) for easy installation.
 
    ```bash
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository ppa:learningequality/kolibri
    ```
 
2.  **Install Kolibri:**
 
    ```bash
    sudo apt-get update
    sudo apt-get install -y kolibri
    ```
 
3.  **Initial Kolibri Setup:**
    -   After installation, Kolibri will be running on `http://127.0.0.1:8080`.
    -   You will need to perform the first-time setup to create a superuser and import content channels.
    -   **Kolibri Superuser:** `him`
    -   **Password:** `ABCD_1234`
 
4.  **Import Content:** Use the Kolibri interface to import the required educational channels. Alternatively, if you have a cloned NVMe drive with content, you can copy the Kolibri content database.
 
---
 
### Part 3: Walled Garden Setup
 
This step configures the Wi-Fi access point and captive portal.
 
1.  **Clone this Repository:**
 
    ```bash
    # First, install git
    sudo apt-get install -y git
 
    # Clone the repository into the user's home directory
    git clone https://github.com/chobyong/kolibri.git /home/him/walled_garden
    cd /home/him/walled_garden
    ```
 
2.  **Install Required Packages:**
 
    ```bash
    sudo apt-get install -y hostapd dnsmasq iptables
    ```
 
3.  **Prepare System:** Stop the default services, as our scripts will manage them manually.
 
    ```bash
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    ```
 
4.  **Make Scripts Executable:**
 
    ```bash
    chmod +x ./start_ap.sh ./stop_ap.sh ./iptables_rules.sh
    ```
 
---
 
### Part 4: Usage
 
#### Start the Walled Garden
 
Run the start script with `sudo`. This will configure the network, start all services, and apply the firewall rules.
 
```bash
sudo ./start_ap.sh
```

How to test
-----------

1. On a client device, connect to the SSID `HIM-GUATE02` using the passphrase `1234567890`.
2. The client should receive an IP in the `192.168.50.x` range.
3. Open a browser and try visiting any site; you should be redirected to the portal page.

Next steps and hardening
------------------------

- Use `iptables-save` to persist rules or move to `nftables` if preferred.
- Use a proper web server (nginx) for production and provide a nicer portal with login/terms.
- For captive-portal detection to work on all OSes, consider returning correct HTTP status codes and headers; sometimes OSes use HTTPS-based probes which complicates interception.

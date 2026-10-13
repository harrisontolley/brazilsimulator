# Brazil Simulator

## Install (Windows)

1. **Download Godot 4.7**
   Go to https://godotengine.org/download/windows and click the big **Godot Engine** download button.
   (Get the normal one, not the ".NET" one.)

2. **Unzip Godot**
   Right-click the downloaded zip, choose **Extract All**. No installer needed.

3. **Download the game**
   Go to https://github.com/harrisontolley/brazilsimulator, click the green **Code** button, then **Download ZIP**.

4. **Unzip the game**
   Right-click the zip, choose **Extract All**.

5. **Open Godot**
   Double-click the Godot `.exe` you extracted in step 2.
   If Windows shows a blue warning, click **More info**, then **Run anyway**.

6. **Import the game**
   Click **Import**, open the game folder from step 4, select `project.godot`, then click **Import & Edit**.

7. **Wait**
   The first load takes a minute while Godot prepares the files.

8. **Play**
   Press **F5**.

## Next time

Open Godot, double-click **Brazil Simulator** in the list, press **F5**.

## Play with a friend

You both need the **same build**: the same download, or the same version of the project. The game turns you away with a message if they differ.

**Host**

1. Open the game, type your name and click **Host match**.
2. Windows asks about the firewall. Tick **Private** and **Public**, then **Allow access**.
3. The top of the screen says **Friend joins with ...** and the address is already copied. Press **Esc** to see every address with a **Copy** button. Send one to your friend.

**Friend**

1. Open the game, type your name.
2. Paste the address into **Host IP** and click **Join match**.

Which address to send:

- **Over the internet** is for a friend in another house. It shows up when your router opens the port by itself.
- **Same Wi-Fi or LAN** is for someone on your own network.
- **Tailscale** is for the free VPN below.

### The router would not open the port

Many home connections will not let a friend in by themselves. The Esc menu says so. Pick one:

- **Tailscale (easiest).** Both of you install it from tailscale.com and sign in. The host opens the Tailscale admin page, finds their computer under **Machines**, chooses **Share** and sends the invite to the friend. The friend accepts. The friend then joins with the host's address that starts with `100.` (it is in the Esc menu under Tailscale).
- **Port forward.** In the router's settings, forward **UDP port 24565** to the host's computer. The friend joins with the host's public address (search "what is my ip").

### Not working?

- **"Different builds"**: you are not both on the same download.
- **"Could not reach the host"**: check the address for typos, that the host clicked Allow on the firewall, and that the host is actually hosting.
- **Windows says "protected your PC"**: click **More info**, then **Run anyway**. The game is not signed.
- **Port 24565 is taken**: start with `-- --port=24570` on both sides, or type `address:24570` in Host IP.

## Making a build to send

1. In Godot: **Editor > Manage Export Templates > Download and Install** (once).
2. **Project > Export**, pick **Windows Desktop**, **Export Project**. Or from a terminal:
   `godot --headless --export-release "Windows Desktop" build/BrazilSimulator.exe`
3. Zip `build/BrazilSimulator.exe` and send it.

Change `config/version` in `project.godot` whenever the networking changes, so older builds are turned away instead of misbehaving.

## Not working?

- **Black screen or crash on start:** update your graphics drivers. The game needs a graphics card that supports Vulkan.
- **"Project was made with a newer version":** you have an older Godot. Download 4.7 again from step 1.

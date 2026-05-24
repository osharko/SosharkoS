# SOsharkOS — pacchetti & decisioni

Documento di lavoro: **flagga** `[x]` ciò che vuoi dentro, lascia `[ ]` ciò che
no, **aggiungi** righe libere. Dove c'è **⚖️ DECISIONE** scegli *una* sotto-opzione.
Niente è ancora nel Containerfile finché non chiudiamo questo doc.

## Legenda metodo d'installazione

| Tag | Significato | Dove finisce |
|---|---|---|
| 🟢 **native** | `dnf install` (repo Fedora) | dentro l'immagine |
| 🔵 **COPR** | `dnf copr enable …` | dentro l'immagine |
| 🟣 **rpmfusion** | richiede repo RPM Fusion | dentro l'immagine |
| 🟠 **flatpak** | Flathub, via `flatpaks.list` | **primo boot** (non nell'image) |
| 🟡 **mise/cargo** | per-utente, runtime tool | non nell'image |
| ⚪ **self-host** | container/quadlet (servizio) | non è un'app desktop |

> Regola immutabile: app **GUI** → preferire 🟠 flatpak (aggiornabili senza
> rebuild, sandbox). Solo le poche meglio supportate native restano 🟢/🔵/🟣.

---

## 0 · Base image — ⚖️ DECISIONE

- [x] 🟢 `quay.io/fedora/fedora-bootc:44` — **consigliato**: base minimale, niente
      DE, fatta per costruirci sopra (oggi nel Containerfile c'è ancora `:42`, da
      aggiornare a `:44`)
- [ ] alternativa: partire da un'immagine Universal Blue (es. Bazzite) per
      ereditare il layer gaming già pronto — *ma* porta con sé KDE/GNOME, contro
      Niri/Noctalia. Sconsigliato; semmai la usiamo come *riferimento*.

---

## 1 · Desktop & shell core (già nel Containerfile)

- [x] 🔵 niri (COPR yalter) · 🟢 noctalia-shell + quickshell (Terra) · 🟢 greetd
- [x] 🟢 fish · 🟢 starship
- [x] 🟢 **alacritty**
- [x] 🟢 **ghostty** — COPR `scottames/ghostty` (non ancora in repo Fedora)
      *nota: ghostty supporta il kitty graphics protocol (immagini inline);
      alacritty no.*

---

## 2 · Utility da terminale

- [x] 🟢 bat · eza · fd-find · ripgrep · fzf · jq · yq · gum (già presenti)
- [x] 🟢 **chafa** — *il viewer immagini "serio"* (protocolli sixel/kitty/iterm,
      fallback unicode). Questo è "l'altro non-icat".
  - [x] lasciar perdere icat e tenere solo **chafa**
- [x] **mdcat** (render markdown nel terminale) — ⚖️:
  - [x] 🟢 native se in repo Fedora (`dnf install mdcat`, da verificare)
  - [x] 🟡 fallback `mise`/`cargo install mdcat`

---

## 3 · Editor & Markdown

- [x] 🟠 **Obsidian** — flatpak `md.obsidian.Obsidian` (richiede vault)
- [ ] **Editor "apri .md al volo" tipo Typora** — ⚖️ DECISIONE (uno):
  - [x] 🟠 **Mark Text** `com.github.marktext.marktext` — *il più simile a Typora*

---

## 4 · Launchpad (già deciso, nel Containerfile)

- [x] 🟢 podman · buildah · skopeo · podman-compose
- [x] 🟢 **docker** (`moby-engine`) + docker.socket
- [x] 🟢 **distrobox**
  - [x] 🟠 **BoxBuddy** (`io.github.dvlv.boxbuddyrs`, flatpak 1° boot) — GUI per
        gestire le box distrobox (crea/avvia/elimina, app graphiche). Solo
        flatpak ufficiale → niente nativo; va in `flatpaks.list`, non nell'image.
- [x] 🟢 **kubectl** (`kubernetes-client`)  ·  helm/k9s/krew → 🟡 mise per-utente
- [x] 🟢 **virt-manager** + qemu-kvm + libvirt  ·  🟢 **quickemu** (incl. quickget)
- [x] 🟢 **bottles** mi sere qualcosa di facilmente funzionante e configurabile, gnome boxes mi pare avesse problemi nel propagare l'ip, ma altrimenti idealmente qualcosa che sia in grado di essere configurato e avviarsi velocemente e che propaghi l'ip sulla LAN (simil proxmox per intenderci) e con una buona dashboard per monitorare, interrompere, etc
- [x] 🔵→🟢 **mise** (repo ufficiale mise.jdx.dev)
- [x] 🟢 **flatpak** + Flathub + 🟠 **Bazaar** (store, `io.github.kolunmi.Bazaar`)

---

## 5 · Password / vault — ⚖️ DECISIONE (chiarito Vaultwarden)

- [x] 🟢 **1Password** + 1password-cli (repo ufficiale) — app neutra, login utente

---

## 6 · Antivirus / security — ⚖️ DECISIONE (Malwarebytes non c'è su Linux)

- [x] 🟢 **ClamAV** (`clamav` + `clamd` + `clamav-update`) — scanner FOSS on-demand
  - [x] 🟢 **ClamTk** — GUI per ClamAV
  - [ ] 🟢 **clamonacc** — scansione on-access (real-time-ish; più carico)
- [x] 🟢 **rkhunter** e/o 🟢 **chkrootkit** — rootkit scanner (scheduled)
- ⚖️ profilo: solo scanner schedulato (leggero) **oppure** on-access (clamonacc)?

---

## 7 · Gaming — ⚖️ DECISIONE

- [ ] **Steam**:
  - [x] 🟣 native RPM Fusion `steam` — miglior integrazione/host graphics, ma
        serve abilitare RPM Fusion nel Containerfile
- [x] 🟢 **gamemode** (`gamemoderun`) — boost performance on-demand
- [x] 🟢 **mangohud** — overlay FPS/stats
- [ ] **Supporto gamepad/controller**:
  - [ ] 🟣 `steam-devices` (udev rules, RPM Fusion) — accesso ai controller
  - [ ] 🔵 `xone`/`xpadneo` (COPR) — solo per Xbox wireless/dongle, se serve
  - [ ] base: la maggior parte dei pad funziona già col kernel (xpad integrato)

---

## 8 · Plumbing desktop base — fedora-bootc è minimale, NON c'è di default

> `packages.yaml` lo ometteva perché la spin CachyOS lo dava gratis. Su
> fedora-bootc va aggiunto a mano, altrimenti niente audio/bt/gpu/login pulito.
> Pre-flaggo gli **essenziali** (senza questi il desktop non è usabile).

- [x] 🟢 **Audio**: pipewire, wireplumber, pipewire-pulseaudio, pipewire-alsa
- [x] 🟢 **Rete**: NetworkManager (+ NetworkManager-wifi) — *verificare se già in base*
- [x] 🟢 **Bluetooth**: bluez (+ bluez-tools)
- [x] 🟢 **GPU/Mesa**: mesa-dri-drivers, mesa-vulkan-drivers, vulkan-loader
      (per gaming 32-bit anche le varianti `.i686` — vedi §7/§9)
- [x] 🟢 **Polkit**: polkit + un agente auth (il plugin Noctalia `polkit-agent`
      fa da UI, ma serve il backend polkit presente)
- [x] 🟢 **Power/brightness**: power-profiles-daemon, brightnessctl, playerctl
- [x] 🟢 **Portals**: xdg-desktop-portal (+ -gtk/-gnome già nel Containerfile)
- [x] 🟢 **Keyring/secrets**: gnome-keyring + libsecret (per 1P/Bitwarden/app)
- [x] 🟢 **xdg-user-dirs**, **xdg-utils** (Downloads/Documents + open handler)
- [ ] 🟢 **Stampa** (opz.): cups, cups-pdf

## 9 · Multimedia & codec — "il fix Fedora per funzionare come Arch"

> Fedora spedisce codec monchi per licenze. Questo è il pacchetto di
> work-around *canonico*, fatto **una volta nell'immagine** così a valle "just
> works" come Arch. RPM Fusion serve comunque per Steam (§7) → dipendenza
> condivisa. Su bootc i `dnf swap`/`--allowerasing` girano a build-time (ok).

- [x] 🟣 **RPM Fusion** free + nonfree (`rpmfusion-free-release` + `-nonfree-release`)
- [x] 🟣 **ffmpeg pieno**: `dnf swap ffmpeg-free ffmpeg --allowerasing`
- [x] 🟣 **GStreamer**: gstreamer1-plugins-{good,bad-free,bad-freeworld,ugly},
      gstreamer1-plugin-openh264, gstreamer1-libav
- [x] 🟢 **openh264** (repo fedora-cisco-openh264, di solito già abilitato) +
      mozilla-openh264 (h264 in Firefox)
- [x] 🟣 **VAAPI hardware decode**:
  - [x] AMD: `dnf swap mesa-va-drivers mesa-va-drivers-freeworld`
        (+ `mesa-vdpau-drivers-freeworld`)
  - [x] Intel: intel-media-driver (+ libva-intel-driver per GPU vecchie)
  - [x] NVIDIA: akmod-nvidia + nvidia-vaapi-driver — *attenzione: akmod va
        ricompilato contro il kernel CachyOS (COPR), possibile attrito*
- [x] 🟣 **libavcodec-freeworld** (h264 hw in Chromium/Brave/Electron)
- [x] 🟣 **mesa-vulkan-drivers-freeworld** (decode **Vulkan**, oltre a VA-API)
- [x] 🟣 **H.265 / HEVC**: ffmpeg pieno (libx265) + libavcodec-freeworld +
      mesa-va-drivers-freeworld (decode HW) — copre play/encode HEVC
- [x] 🟢 **AV1**: royalty-free → già in ffmpeg-free (decode dav1d); encode
      svt-av1 / rav1e / libaom (🟢 Fedora)
- [x] 🟣 **AAC**: libfdk-aac-free (o via ffmpeg pieno)
- [ ] ⚠️ **H.266 / VVC**: NON ancora pacchettizzato in Fedora/RPM Fusion
      (vvenc/vvdec esistono upstream ma fuori repo) → bleeding edge, escluso per ora
- [x] 🟢 **libva-utils** (`vainfo`) per verificare l'accelerazione HW
- ℹ️ comodo: `dnf group install multimedia` tira buona parte del set sopra.

## 10 · CLI / TUI extra (da packages.yaml, non ancora coperti)

- [x] 🟢 git-delta, neovim (lazyvim), tmux, direnv, aria2, zoxide
- [x] 🟢 dust, duf, procs, tealdeer (tldr), qt6ct
- [x] 🟢 cliphist (storia clipboard — **richiesto da Noctalia clipboard plugin**)
- [x] 🔵 lazygit, lazydocker, lazyjournal — *verificare repo Fedora, altrimenti COPR/binari*
- [ ] X gh (github-cli) → via distrobox se necessario, non lo vedo utile metterlo per tutti

## 11 · Niri: lock/idle + deps plugin Noctalia

> Senza lock/idle Niri è "nudo". I deps plugin servono **solo se** spediamo i
> plugin Noctalia di default (decisione sotto).

- [x] 🔵 **hyprlock** + **hypridle** + **hyprpicker** (lock/idle/color-picker per Niri)
- [x] **Deps plugin Noctalia** — *RICHIESTI tutti* (decisione: spediamo il set
      di plugin attuale, quindi servono tutte le deps):
  - [x] 🟢 grim, slurp (già nel Containerfile), tesseract (+eng), translate-shell
  - [x] 🔵 wl-screenrec, gifski, gpu-screen-recorder (probabili COPR)
  - [x] 🟢 udisks2, ntfs-3g (usb-drive-manager) · evtest (slowbongo, gruppo `input`)
- ✅ **DECISIONE PRESA**: Noctalia con le impostazioni attuali → l'immagine deve
  supportare **tutti** i plugin previsti adesso (deps sopra tutte incluse).
  La lista plugin/deps va tenuta in sync con `configure-work-machine`
  `.chezmoidata/packages.yaml` → `noctalia_plugins:`.

## 12 · App desktop & editor

> Tua direttiva: **VSCodium + IntelliJ** li vogliamo; il resto al massimo Flatpak.

**Editor**
- [x] 🔵 **VSCodium** — repo RPM ufficiale (download.vscodium.com) · in alt. 🟠 `com.vscodium.codium`
- [x] 🟠 **IntelliJ IDEA** — flatpak `com.jetbrains.IntelliJ-IDEA-Community`
      (o JetBrains Toolbox) ▸ *accorgimento: 🟢 nativo NON esiste, niente RPM repo*
- [x] 🟢 **Sublime Text** — repo RPM ufficiale (sublimetext.com)

**App** (viewer leggeri → native; chat/browser → flatpak)
- [x] 🟢 mpv · imv · evince · seahorse (keyring GUI)
- [x] 🟢 **Telegram** (rpmfusion `telegram-desktop`) ▸ *Signal rimosso (non serve)*
- [x] 🟢 **Brave** (repo ufficiale `brave-browser`) — browser di default? ⚖️
- [x] 🟠 **Blanket** (flatpak `com.rafaelmardojai.Blanket`) ▸ *accorgimento: solo flatpak*

## 13 · VM management "Proxmox-like" (risposta alla tua nota in §4)

> ⚠️ **Bottles non è un VM manager**: è un gestore di *prefissi Wine* per far
> girare **app Windows** (non VM). Quello che descrivi (IP sulla LAN, dashboard
> monitor/stop, avvio rapido, stile Proxmox) è gestione VM. Li separo:

- [x] **Dashboard VM web (il tuo "simil-Proxmox")** — ⚖️:
  - [x] solo virt-manager (desktop, già incluso) — niente web dashboard
- [x] **IP sulla LAN (non NAT)**: serve un **bridge** `br0` sulla NIC (via
      NetworkManager) al posto della rete NAT `virbr0` → le VM prendono IP dal
      router come Proxmox. (lo predispongo come opzione/doc, non forzato)
- [x] 🟠 **Bottles** `com.usebottles.bottles` — *separato*, solo se vuoi far
      girare app/giochi **Windows** via Wine (≠ VM)

## 14 · Fonts

- [x] 🟢 jetbrains-mono-fonts, cascadia-code-fonts, fontawesome-fonts, google-noto(+emoji)
- [x] 🔵 varianti **Nerd Font** patchate (cascadia/jetbrains nerd) → COPR o manuale
      (Fedora non packagizza tutte le Nerd Font)
- [x] iA Writer (Duospace) → COPR/manuale (era AUR)

## 15 · Gamepad / controller (lo avevi chiesto; §7 "controller" era vuoto)

- [x] 🟣 **steam-devices** (udev rules) — minimo per far vedere i pad ai giochi
- [x] 🔵 **xpadneo** (Xbox BT) / **xone** (Xbox USB/dongle) — via **akmod/COPR**
      ⚠️ va buildato contro il kernel CachyOS (COPR) → possibile attrito akmod;
      se rognoso, si parte con steam-devices e si aggiunge dopo
- [x] base kernel: Stadia/Steam Controller/8BitDo/PS spesso già OK (hid built-in)

---

## 16 · Emulazione / Virtualizzazione / Traduzione app (spunti da Bazzite)

> L'idea: poter **eseguire qualsiasi app utile** — Linux di altre distro,
> Windows, retro — senza toccare l'immutabile. Bazzite (Fedora atomic gaming)
> fa da riferimento: Proton/Wine, gamescope, protontricks, umu-launcher,
> vkBasalt, MangoHud + opzionali EmuDeck/RetroDECK/Decky.

**App Linux di altre distro** → 🟢 **distrobox** (già §4)

**App Android (stile WSA — Windows Subsystem for Android)**
- [x] 🟢 **Waydroid** — Android in un container **LXC**, app come **finestre native**
      su Niri/Wayland. `waydroid` è in **base Fedora 44** (verificato dry-run:
      `waydroid-1.6.2` dal repo `fedora`; **NIENTE COPR** — il COPR
      `aleasto/waydroid` ha solo `1.3.4`, più vecchio → preferiamo la base, più
      stabile e non flaky). Deps: 🟢 `lxc` `dnsmasq` `python3-gbinder`
      `python3-dbus` `python3-gobject` (tutte base Fedora). Va **nell'immagine**
      (solo il pacchetto), in `Containerfile` Layer 6e (gaming/emulazione).
  - **Binder kernel (CRITICO)**: Waydroid richiede `CONFIG_ANDROID_BINDER_IPC`
    e `CONFIG_ANDROID_BINDERFS`. Verificato sul config del kernel CachyOS COPR
    (`bieszczaders/kernel-cachyos` 7.0.8, in
    `/usr/lib/modules/$KVER/config`): **`CONFIG_ANDROID_BINDER_IPC=y` +
    `CONFIG_ANDROID_BINDERFS=y` → entrambi BUILT-IN (`=y`)**. Quindi NESSUN
    `/etc/modules-load.d/*.conf` (non esiste un `binder_linux.ko` da caricare; il
    filesystem binderfs è compilato nel kernel — il pacchetto monta
    `dev-binderfs.mount` su `/dev/binderfs`). Coerente col kernel host Arch
    CachyOS dell'utente (anche lì `=y`+`=y`).
  - **Dati in `/var`**: `waydroid init` scarica le immagini system/vendor e
    scrive in `/var` (scrivibile su bootc) → **NON** si esegue a build-time
    (serve rete + scrittura). Solo il pacchetto è cotto nell'immagine.
  - **androidbox — UX Android a livello OS (NIENTE distrobox/repo separati)**.
    Tre helper in `/usr/bin/` (sorgenti in `build_files/androidbox-*.sh`) +
    una **user unit** `waydroid-session.service` in `/usr/lib/systemd/user/`:
    - **`waydroid-container.service` (SYSTEM) ships DISABILITATO di default**
      nell'immagine: **zero consumo di risorse finché non opti-in** (cambiato
      rispetto al commit `a2d7057` che lo `enabled`-va). Niente altro auto-avvia
      Android al boot.
    - **Opt-in PERSISTENTE** (torna a ogni boot/login finché non lo spegni),
      ottenuto via `systemctl enable` (enable = persiste tra i reboot):
      - **`androidbox-start`** = (init one-time se serve) →
        `sudo systemctl enable --now waydroid-container` (system) →
        attende il container → `systemctl --user enable --now
        waydroid-session.service` (user) → `waydroid prop set
        persist.waydroid.multi_windows true` (+ `persist.waydroid.gralloc gbm`,
        hint AMD/mesa, difensivo). Stampa come lanciare le app e la nota di
        certificazione Play Store. Il **primo** avvio esegue `sudo waydroid init
        -s GAPPS` (download ~1GB system/vendor con Google Apps, serve rete).
      - **`androidbox-stop`** = `waydroid session stop` (best-effort) →
        `systemctl --user disable --now waydroid-session.service` →
        `sudo systemctl disable --now waydroid-container`. Spento e **non torna
        al boot**.
      - **`androidbox-status`** = `waydroid status` + is-enabled/is-active di
        entrambe le unit (container system + session user) + inizializzato sì/no.
    - **User session service** (`waydroid-session.service`): la sessione ha
      bisogno del display **Wayland** → può partire SOLO dopo il login grafico,
      non al boot puro. È `PartOf`/`WantedBy=graphical-session.target`,
      `Requisite=waydroid-container.service`, `ExecStart=/usr/bin/waydroid
      session start`, `Restart=on-failure RestartSec=10` (non martella se il
      container è giù). **NON** è enabled di default nell'immagine: lo abilita
      per-utente `androidbox-start`.
    - **Multi-window**: con `persist.waydroid.multi_windows true` ogni app
      Android gira in una **finestra host dedicata** (no UI unica); le app
      esportano launcher `.desktop` propri → avviabili dal **launcher del
      desktop** senza comandi manuali una volta attivate.
  - **Primo uso (runtime, l'utente)** — basta `androidbox-start` (fa tutto):
    1. one-time `sudo waydroid init -s GAPPS` (download ~1GB con Google Apps;
       senza `-s GAPPS` sarebbe `VANILLA`, no Play Store).
    2. abilita+avvia container (system) e sessione (user), imposta multi-window.
    3. lancia le app dal launcher o con `waydroid app launch <id>` /
       `waydroid show-full-ui`.
  - **Play Store — certificazione (richiesta con GAPPS)**: il device va
    certificato o il Play Store dice "not certified". Recupera l'`android_id`
    (`sudo waydroid shell`→`ANDROID_RUNTIME_ROOT=/apex/com.android.runtime
    sqlite3 /data/data/com.google.android.gsf/databases/gservices.db
    "select * from main where name = 'android_id';"`) e registralo su
    **https://www.google.com/android/uncertified/**, poi attendi/riavvia.
- [ ] (alt) Android via emulatore (Genymotion/Anbox) — scartato: Waydroid è il
      più integrato con Wayland e mantenuto.

**App Windows (traduzione/compat)**
- [x] 🟢 **Wine** + **winetricks** (Fedora repos) — base per app Windows
- [x] 🟠 **Bottles** `com.usebottles.bottles` (gestione prefissi Wine, già §13)
- [x] **WinBoat** — Windows in container Docker/Podman+**KVM**, app come finestre
      Linux native via **FreeRDP + RemoteApp**. Usa docker+kvm (✓ §4) + 🟢 **freerdp**.
      Install: release GitHub `TibixDev/winboat` (AppImage; verificare flatpak/rpm).
      ⚖️ lo teniamo, poi valuti se rimuovere.
- [ ] (alt) **WinApps** — app Windows via VM+FreeRDP (script, no pkg) — alternativa a WinBoat

**Gaming compat (stile Bazzite)**
- [x] 🟢 **gamescope** (micro-compositore per giochi) · gamemode/mangohud (✓ §7)
- [ ] 🔵 protontricks, umu-launcher, vkBasalt (probabili COPR/flatpak)

**Emulatori retro** (tutti 🟠 flatpak, installabili da Bazaar — non nell'image)
- [ ] RetroArch `org.libretro.RetroArch` · RetroDECK `net.retrodeck.retrodeck`
- [ ] Dolphin · PCSX2 · RPCS3 · PPSSPP · ScummVM · DOSBox-Staging (flatpak)

**Full VM**: qemu/virt-manager/quickemu (§4) + bridge LAN (§13)

## 17 · Install opzionale a runtime (NON immutabile) — onboarding primo boot

> Chiarimento: i **package manager** (mise · brew · flatpak · distrobox) sono la
> BASE sempre presente del launchpad (immutabile), **non** opzionali. Ciò che è
> opt-in è **cosa installi ATTRAVERSO di loro** al primo boot — runtime, formule,
> app, container — tutto in `/home`/`/var`, non tocca l'immagine. Wizard
> `sosharkos-onboard` (gum TUI) al primo login con default pre-flaggati
> **deselezionabili**. Distinto da `flatpaks.list` (baseline non interattiva).

**Canali (sempre nell'immagine):** 🟢 mise · 🟠 flatpak · 🟢 distrobox ·
🟡 **brew** (bootstrap al primo boot in `/home/linuxbrew`)

**Default pre-flaggati installati al primo boot (ogni voce opt-out):**
- [x] 🟡 **mise** runtime LTS: **python · node · java · go · dotnet** (estendibile)
- [x] 🟡 **brew**: bootstrap (+ eventuali formule base da concordare)
- [x] 🟠 **flatpak extra** oltre la baseline (lista da concordare)
- [x] 🟢 **distrobox**: box preconfigurati opzionali (es. fedora/ubuntu dev)
- meccanismo: checklist `gum` al primo login, idempotente, ogni voce opt-out

## 18 · Install da cmdline / unattended (come quickget)

> Tua richiesta: ISO installabile **senza GUI**, con argomenti preimpostati.

- [x] 🟢 **`bootc install to-disk`** — la via più scriptabile: da live env (o
      dall'immagine come container) → `sudo bootc install to-disk --filesystem
      btrfs /dev/sdX` con flag. Zero GUI, args preimpostati.
- [x] 🟢 **Kickstart** — ISO Anaconda con `inst.ks=<url|path>`: install unattended
      (disk/utente/locale/tastiera preimpostati). Spediamo un `kickstart.ks` esempio.
- [x] bootc-image-builder può produrre anche `qcow2`/`raw` per deploy diretto
- [x] doc dedicato `docs/install.md` (cmdline + kickstart + bootc upgrade/rollback)

---

## Aggiungi qui le tue (libero)

- [ ] …
- [ ] …

---

### Note operative quando chiudiamo il doc
- Le 🟠 flatpak vanno in `build_files/flatpaks.list` (primo boot), non nel build.
- 🟣 rpmfusion: aggiungere il layer repo nel Containerfile (free+nonfree) prima
  di Steam/steam-devices.
- ⚪ Vaultwarden: se sì, va in un doc/quadlet a parte (`docs/vaultwarden.md`),
  fuori dall'immagine base.

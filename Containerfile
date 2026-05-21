# SOsharkOS — immutable bootc desktop, condivisibile.
#
# Filosofia: immagine = "launchpad". Sistema base fisso e riproducibile; tutto
# l'app-specific (dev tools, distro extra, GUI app) si installa SOPRA — via
# distrobox / VM / flatpak / mise / brew — SENZA ricostruire l'immagine.
# Specifica completa delle scelte: docs/packages.md (§0–§18).
#
# Layer 0  Fedora bootc 44 (base)
# Layer 1  RPM Fusion + codec pieni (multimedia "come Arch")  — §9
# Layer 2  kernel CachyOS (COPR bieszczaders)                 — §0
# Layer 3  Niri + Noctalia + greetd                           — §1/§11
# Layer 4  plumbing desktop (audio/net/bt/gpu/polkit/power)   — §8
# Layer 5  LAUNCHPAD: container/kube/VM/mise/flatpak/Bazaar   — §4
# Layer 6  CLI/editor/app/vault/AV/gaming/emulazione          — §2/§5/§6/§7/§10/§12/§16
#
# NESSUNA identità/segreto/config personale è dentro l'immagine.

FROM quay.io/fedora/fedora-bootc:44

# ─── DNF tuning + plugin COPR (dnf5) ─────────────────────────────
RUN sed -i '/^\[main\]/a max_parallel_downloads=10\nfastestmirror=True' /etc/dnf/dnf.conf && \
    dnf -y install dnf5-plugins && dnf clean all

# ═════ Layer 1 · RPM Fusion + Cisco openh264 (codec §9, Steam §7) ═
RUN dnf -y install \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" && \
    dnf config-manager setopt fedora-cisco-openh264.enabled=1 2>/dev/null || true; \
    dnf clean all

# ═════ Layer 2 · Kernel CachyOS + addons (COPR bieszczaders) ═════
# F44: il devel è 'kernel-cachyos-devel-matched' (NON '*-headers').
RUN dnf -y copr enable bieszczaders/kernel-cachyos && \
    dnf -y copr enable bieszczaders/kernel-cachyos-addons && \
    dnf -y install kernel-cachyos kernel-cachyos-devel-matched cachyos-settings scx-scheds && \
    dnf clean all

# ═════ Layer 3 · Niri + Noctalia (COPR) + greetd ════════════════
RUN dnf -y copr enable yalter/niri && \
    dnf -y install niri xdg-desktop-portal-gnome xdg-desktop-portal-gtk && \
    dnf clean all
# noctalia-shell vive nel COPR zhangyi6324; tira noctalia-qs (build quickshell
# dedicata) che CONFLIGGE con il quickshell di Fedora → NON installiamo quello.
RUN dnf -y copr enable zhangyi6324/noctalia-shell && \
    dnf -y install noctalia-shell && dnf clean all
RUN dnf -y install greetd && mkdir -p /etc/greetd && \
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "niri-session"\nuser = "greeter"\n' \
        > /etc/greetd/config.toml && \
    systemctl enable greetd.service
# TODO desktop: niri config di default in /etc/skel con
#   spawn-at-startup "qs" "-c" "noctalia-shell"   (altrimenti niri parte "nudo")

# ═════ Layer 4 · Plumbing desktop base (§8) ══════════════════════
# fedora-bootc è minimale: audio/bt/gpu/polkit/power vanno aggiunti a mano.
RUN dnf -y install \
        pipewire wireplumber pipewire-pulseaudio pipewire-alsa \
        NetworkManager NetworkManager-wifi \
        bluez bluez-tools \
        mesa-dri-drivers mesa-vulkan-drivers vulkan-loader mesa-va-drivers \
        polkit \
        power-profiles-daemon brightnessctl playerctl \
        xdg-desktop-portal xdg-user-dirs xdg-utils \
        gnome-keyring libsecret seahorse && \
    dnf clean all

# ═════ Layer 1b · Codec multimedia pieni (§9) ════════════════════
# ffmpeg-free → ffmpeg pieno; mesa va/vulkan → freeworld (HW decode);
# gstreamer plugins; HEVC(x265)/AV1(svt-av1)/AAC(fdk-aac-free).
# (VDPAU rimosso: mesa-vdpau-drivers non più pacchettizzato su F44; VA-API basta.)
RUN dnf -y swap --allowerasing ffmpeg-free ffmpeg && \
    dnf -y swap --allowerasing mesa-va-drivers mesa-va-drivers-freeworld && \
    dnf -y install \
        gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly gstreamer1-plugin-openh264 gstreamer1-libav \
        libavcodec-freeworld \
        x265 svt-av1 fdk-aac-free \
        openh264 mozilla-openh264 \
        libva-utils && \
    dnf -y swap --allowerasing mesa-vulkan-drivers mesa-vulkan-drivers-freeworld 2>/dev/null || true; \
    dnf clean all

# ═════ Layer 5 · LAUNCHPAD (§4) ══════════════════════════════════
# podman + docker(moby) + distrobox; NIENTE podman-docker (collide con moby).
RUN dnf -y install \
        podman buildah skopeo podman-compose \
        moby-engine distrobox \
        kubernetes-client \
        virt-manager qemu-kvm libvirt-daemon-driver-qemu libvirt-client quickemu \
        flatpak && \
    dnf clean all && \
    systemctl enable docker.socket podman.socket libvirtd.service
# mise (repo ufficiale)
RUN curl -fsSL https://mise.jdx.dev/rpm/mise.repo -o /etc/yum.repos.d/mise.repo && \
    dnf -y install mise && dnf clean all

# ═════ Layer 6a · Terminal + CLI/TUI (§1/§2/§10) ═════════════════
# starship via COPR atim (non in repo Fedora). ghostty via COPR scottames.
# NB §10: mdcat/lazygit/lazydocker NON in repo Fedora → via onboarding (mise/brew).
RUN dnf -y copr enable scottames/ghostty && \
    dnf -y copr enable atim/starship && \
    dnf -y install \
        fish alacritty ghostty starship \
        bat eza fd-find ripgrep fzf jq yq gum chafa \
        git git-delta neovim tmux direnv aria2 zoxide \
        dust duf procs tealdeer qt6ct cliphist \
        wl-clipboard grim slurp && \
    dnf clean all

# ═════ Layer 6b · Niri lock/idle + deps plugin Noctalia (§11) ════
RUN dnf -y copr enable solopasha/hyprland && \
    dnf -y install hyprlock hypridle hyprpicker && \
    dnf -y install \
        tesseract tesseract-langpack-eng translate-shell \
        udisks2 ntfs-3g evtest && \
    dnf clean all
# TODO §11: gpu-screen-recorder / wl-screenrec / gifski (deps plugin Noctalia
# screen-recorder) NON in repo abilitati su F44 → pinnare COPR giusti.
# Best-effort: non bloccare la build.
RUN dnf -y --skip-unavailable install gpu-screen-recorder wl-screenrec gifski 2>/dev/null; \
    dnf clean all || true

# ═════ Layer 6c · Editor + app native (§12) ══════════════════════
RUN rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg && \
    printf '[gitlab.com_paulcarroty_vscodium_repo]\nname=VSCodium\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg\n' \
        > /etc/yum.repos.d/vscodium.repo && \
    dnf -y install codium && dnf clean all
RUN rpmkeys --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg && \
    dnf config-manager addrepo --from-repofile=https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo && \
    dnf -y install sublime-text && dnf clean all
RUN dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo && \
    dnf -y install brave-browser && dnf clean all
RUN dnf -y install mpv imv evince telegram-desktop && dnf clean all

# ═════ Layer 6d · Vault (§5) + Antivirus (§6) ════════════════════
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc && \
    cat > /etc/yum.repos.d/1password.repo <<'EOF' && dnf -y install 1password 1password-cli && dnf clean all
[1password]
name=1Password
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
RUN dnf -y install clamav clamd clamav-update clamtk rkhunter chkrootkit && dnf clean all

# ═════ Layer 6e · Gaming + controller + emulazione (§7/§15/§16) ══
RUN dnf -y install \
        steam gamemode mangohud steam-devices \
        gamescope \
        wine winetricks freerdp && \
    dnf clean all
# TODO §15: xpadneo/xone (Xbox wireless) via akmod contro kernel CachyOS — da
# validare; fallback steam-devices (sopra) già attivo.

# ═════ Layer 7 · Fonts (§14) ═════════════════════════════════════
RUN dnf -y install \
        jetbrains-mono-fonts cascadia-code-fonts fontawesome-fonts-all \
        google-noto-sans-fonts google-noto-emoji-fonts google-noto-color-emoji-fonts && \
    dnf clean all
# TODO §14: Nerd Font patchate + iA Writer via COPR/manuale

# ═════ Flatpak first-boot + os-release + skel ════════════════════
COPY build_files/flatpaks.list /usr/share/sosharkos/flatpaks.list
COPY build_files/sosharkos-flatpak-setup.sh /usr/libexec/sosharkos-flatpak-setup
COPY build_files/sosharkos-flatpak-setup.service /usr/lib/systemd/system/sosharkos-flatpak-setup.service
RUN chmod +x /usr/libexec/sosharkos-flatpak-setup && \
    systemctl enable sosharkos-flatpak-setup.service

COPY build_files/skel/ /etc/skel/

RUN sed -i 's/^NAME="Fedora Linux"/NAME="SOsharkOS"/' /etc/os-release && \
    sed -i 's/^PRETTY_NAME="Fedora Linux.*"/PRETTY_NAME="SOsharkOS (CachyOS-kernel + Niri\/Noctalia)"/' /etc/os-release

RUN rm -rf /var/cache/* /var/log/*.log /tmp/* && \
    bootc container lint

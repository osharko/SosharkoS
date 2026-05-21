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
    dnf config-manager setopt fedora-cisco-openh264.enabled=1 2>/dev/null || true && \
    dnf clean all

# ═════ Layer 2 · Kernel CachyOS + addons (COPR bieszczaders) ═════
RUN dnf -y copr enable bieszczaders/kernel-cachyos && \
    dnf -y copr enable bieszczaders/kernel-cachyos-addons && \
    dnf -y install kernel-cachyos kernel-cachyos-headers cachyos-settings scx-scheds && \
    dnf clean all

# ═════ Layer 3 · Niri + Noctalia + greetd ════════════════════════
RUN dnf -y copr enable yalter/niri && \
    dnf -y install niri xdg-desktop-portal-gnome xdg-desktop-portal-gtk && \
    dnf clean all
RUN curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo \
        -o /etc/yum.repos.d/terra.repo && \
    dnf -y install quickshell noctalia-shell && dnf clean all
RUN dnf -y install greetd && mkdir -p /etc/greetd && \
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "niri-session"\nuser = "greeter"\n' \
        > /etc/greetd/config.toml && \
    systemctl enable greetd.service

# ═════ Layer 4 · Plumbing desktop base (§8) ══════════════════════
# fedora-bootc è minimale: audio/bt/gpu/polkit/power vanno aggiunti a mano.
RUN dnf -y install \
        pipewire wireplumber pipewire-pulseaudio pipewire-alsa pipewire-utils-audio 2>/dev/null; \
    dnf -y install \
        pipewire wireplumber pipewire-pulseaudio pipewire-alsa \
        NetworkManager NetworkManager-wifi \
        bluez bluez-tools \
        mesa-dri-drivers mesa-vulkan-drivers vulkan-loader mesa-va-drivers mesa-vdpau-drivers \
        polkit \
        power-profiles-daemon brightnessctl playerctl \
        xdg-desktop-portal xdg-user-dirs xdg-utils \
        gnome-keyring libsecret seahorse && \
    dnf clean all

# ═════ Layer 1b · Codec multimedia pieni (§9) ════════════════════
# ffmpeg-free → ffmpeg pieno; mesa va/vulkan → varianti freeworld (HW decode);
# gstreamer plugins; HEVC/AV1/AAC. (AV1 è già in ffmpeg-free, qui encode/extra.)
RUN dnf -y swap --allowerasing ffmpeg-free ffmpeg && \
    dnf -y swap --allowerasing mesa-va-drivers mesa-va-drivers-freeworld && \
    dnf -y swap --allowerasing mesa-vdpau-drivers mesa-vdpau-drivers-freeworld && \
    dnf -y install \
        gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly gstreamer1-plugin-openh264 gstreamer1-libav \
        libavcodec-freeworld \
        x265 svt-av1 libfdk-aac-free \
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
RUN dnf -y copr enable scottames/ghostty && \
    dnf -y install \
        fish alacritty ghostty starship \
        bat eza fd-find ripgrep fzf jq yq gum chafa mdcat \
        git git-delta neovim tmux direnv aria2 zoxide \
        dust duf procs tealdeer qt6ct cliphist \
        lazygit \
        wl-clipboard grim slurp && \
    dnf clean all

# ═════ Layer 6b · Niri lock/idle + deps plugin Noctalia (§11) ════
RUN dnf -y copr enable solopasha/hyprland && \
    dnf -y install hyprlock hypridle hyprpicker && \
    dnf -y install \
        tesseract tesseract-langpack-eng translate-shell \
        udisks2 ntfs-3g evtest \
        gpu-screen-recorder wl-screenrec gifski && \
    dnf clean all

# ═════ Layer 6c · Editor + app native (§12) ══════════════════════
# VSCodium (repo ufficiale)
RUN rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg && \
    printf '[gitlab.com_paulcarroty_vscodium_repo]\nname=VSCodium\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg\n' \
        > /etc/yum.repos.d/vscodium.repo && \
    dnf -y install codium && dnf clean all
# Sublime Text (repo ufficiale)
RUN rpmkeys --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg && \
    dnf config-manager addrepo --from-repofile=https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo && \
    dnf -y install sublime-text && dnf clean all
# Brave (repo ufficiale)
RUN dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo && \
    dnf -y install brave-browser && dnf clean all
# App native leggere + Telegram (rpmfusion)
RUN dnf -y install mpv imv evince telegram-desktop && dnf clean all

# ═════ Layer 6d · Vault (§5) + Antivirus (§6) ════════════════════
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc && \
    printf '[1password]\nname=1Password\nbaseurl=https://downloads.1password.com/linux/rpm/stable/%%{_arch}\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc\n' \
        > /etc/yum.repos.d/1password.repo && \
    dnf -y install 1password 1password-cli && dnf clean all
RUN dnf -y install clamav clamd clamav-update clamtk rkhunter chkrootkit && dnf clean all

# ═════ Layer 6e · Gaming + controller + emulazione (§7/§15/§16) ══
RUN dnf -y install \
        steam gamemode mangohud steam-devices \
        gamescope \
        wine winetricks freerdp && \
    dnf clean all
# xpadneo/xone (Xbox wireless): akmod contro kernel CachyOS — best-effort,
# non blocca la build se l'akmod non compila (vedi docs/packages.md §15).
# TODO: validare akmod vs kernel-cachyos; fallback steam-devices già installato.

# ═════ Layer 7 · Fonts (§14) ═════════════════════════════════════
RUN dnf -y install \
        jetbrains-mono-fonts-all cascadia-code-fonts fontawesome-fonts-all \
        google-noto-sans-fonts google-noto-emoji-fonts google-noto-color-emoji-fonts \
        2>/dev/null; \
    dnf -y install jetbrains-mono-fonts cascadia-code-fonts \
        google-noto-sans-fonts google-noto-color-emoji-fonts && \
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

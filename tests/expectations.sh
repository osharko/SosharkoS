#!/usr/bin/env bash
# Spec dichiarativa di cosa l'immagine DEVE contenere.
# Single source of truth dei test — tieni allineato a docs/packages.md.
#
# NB: questo file è la "specifica eseguibile". Finché il Containerfile non
# implementa una sezione, i relativi check FALLISCONO: è il comportamento
# voluto (rosso → verde man mano che aggiungiamo). Commenta le righe che non
# vuoi ancora testare.

# ─── Binari attesi nel PATH (command -v) ────────────────────────────
EXPECT_BINS=(
  # desktop & shell core
  niri fish alacritty ghostty starship
  # terminal utils (§2) — mdcat/lazygit via onboarding (mise/brew), non nell'image
  bat eza fd rg fzf jq yq gum chafa
  # emulazione/traduzione (§16)
  wine winetricks gamescope
  # launchpad (§4)
  podman docker buildah skopeo distrobox
  kubectl virt-manager quickemu quickget mise flatpak
  # vault (§5)
  op
  # antivirus (§6)
  clamscan freshclam rkhunter
  # gaming (§7)
  steam gamemoderun mangohud
  # plumbing base (§8)
  pipewire wireplumber nmcli bluetoothctl brightnessctl playerctl
  # codec (§9)
  ffmpeg
  # niri lock/idle (§11)
  hyprlock hypridle hyprpicker
  # editor (§12)
  codium
)

# ─── RPM attesi (rpm -q) ────────────────────────────────────────────
EXPECT_RPMS=(
  # kernel + desktop
  kernel-cachyos cachyos-settings scx-scheds
  niri noctalia-shell noctalia-qs greetd
  # plumbing (§8)
  pipewire wireplumber pipewire-pulseaudio
  NetworkManager bluez polkit
  mesa-vulkan-drivers-freeworld vulkan-loader
  power-profiles-daemon gnome-keyring
  # launchpad (§4)
  moby-engine distrobox
  virt-manager qemu-kvm mise flatpak
  # vault + av
  1password 1password-cli clamav rkhunter
  # codec (§9)
  rpmfusion-free-release rpmfusion-nonfree-release
  libavcodec-freeworld
  # editor
  codium
)

# ─── Unit systemd che devono risultare 'enabled' (offline) ──────────
EXPECT_UNITS_ENABLED=(
  greetd.service
  docker.socket
  podman.socket
  libvirtd.service
  sosharkos-flatpak-setup.service
)

# ─── File che devono esistere nell'immagine ─────────────────────────
EXPECT_FILES=(
  /usr/share/sosharkos/flatpaks.list
  /usr/libexec/sosharkos-flatpak-setup
  /usr/lib/systemd/system/sosharkos-flatpak-setup.service
  /etc/greetd/config.toml
  /etc/yum.repos.d/mise.repo
)

# ─── /etc/os-release deve contenere questa stringa ──────────────────
EXPECT_OSRELEASE_GREP="SOsharkOS"

# ─── ffmpeg deve esporre questi encoder (verifica layer codec §9) ───
EXPECT_FFMPEG_ENCODERS=( libx264 libx265 )

# ─── Flatpak che devono essere nella lista first-boot ───────────────
EXPECT_FLATPAKS=(
  io.github.kolunmi.Bazaar
  md.obsidian.Obsidian
  com.github.marktext.marktext
  com.jetbrains.IntelliJ-IDEA-Community
)

# SOsharkOS — immutable bootc desktop, condivisibile.
#
# Filosofia: immagine = "launchpad". Il sistema base è fisso e riproducibile;
# tutto l'app-specific (dev tools, cloud CLI, distro extra, GUI app) si installa
# SOPRA — via distrobox / VM / flatpak / mise — SENZA ricostruire l'immagine.
#
# Layer 0: Fedora bootc 42 (base canonica)
# Layer 1: kernel CachyOS + scheduler addons (COPR bieszczaders)
# Layer 2: Niri compositor + Noctalia shell + greetd
# Layer 3: LAUNCHPAD — container runtimes, kube, VM tooling, mise, flatpak/Bazaar
# Layer 4: app neutre native (1Password) + flatpak al primo boot (Bazaar, Bitwarden)
#
# NESSUNA identità/segreto/config personale è dentro l'immagine: l'utente
# (chiunque) fa login alle proprie app, applica i propri dotfile, crea i propri
# distrobox/VM dopo il primo boot.
#
# Refs:
# - bootc: https://bootc-dev.github.io/bootc/
# - Universal Blue (pattern flatpak first-boot): https://github.com/ublue-os/image-template
# - CachyOS kernel COPR: https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/
# - Niri COPR: https://copr.fedorainfracloud.org/coprs/yalter/niri/
# - Noctalia (Terra repo): https://github.com/terrapkg/subatomic-repos
# - Bazaar: https://flathub.org/apps/io.github.kolunmi.Bazaar

FROM quay.io/fedora/fedora-bootc:42

# ─── DNF tuning ──────────────────────────────────────────────────
RUN sed -i '/^\[main\]/a max_parallel_downloads=10\nfastestmirror=True' /etc/dnf/dnf.conf

# ─── Layer 1 · Kernel CachyOS + addons (COPR bieszczaders) ───────
# dnf5-plugins fornisce il comando `dnf copr` su Fedora 42 (dnf5).
RUN dnf -y install dnf5-plugins && \
    dnf -y copr enable bieszczaders/kernel-cachyos && \
    dnf -y copr enable bieszczaders/kernel-cachyos-addons && \
    dnf -y install \
        kernel-cachyos \
        kernel-cachyos-headers \
        cachyos-settings \
        scx-scheds && \
    dnf clean all

# ─── Layer 2 · Niri compositor ───────────────────────────────────
RUN dnf -y copr enable yalter/niri && \
    dnf -y install niri xdg-desktop-portal-gnome xdg-desktop-portal-gtk && \
    dnf clean all

# ─── Layer 2 · Noctalia + Quickshell (Terra repo) ────────────────
RUN curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo \
        -o /etc/yum.repos.d/terra.repo && \
    dnf -y install quickshell noctalia-shell && \
    dnf clean all

# ─── Layer 2 · greetd (tty1 → niri session) ──────────────────────
RUN dnf -y install greetd && \
    mkdir -p /etc/greetd && \
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "niri-session"\nuser = "greeter"\n' \
        > /etc/greetd/config.toml && \
    systemctl enable greetd.service

# ─── Layer 2 · host base (shell, terminal, file tooling) ─────────
RUN dnf -y install \
        fish alacritty starship \
        git \
        bat eza fd-find ripgrep fzf \
        jq yq gum \
        wl-clipboard grim slurp \
        && dnf clean all

# ═════════════════════════════════════════════════════════════════
# Layer 3 · LAUNCHPAD — strumenti per installare/eseguire qualsiasi
#           cosa senza ricostruire l'immagine.
# ═════════════════════════════════════════════════════════════════

# ─── Container runtimes: podman + docker (moby) + distrobox ───────
# NB: moby-engine fornisce /usr/bin/docker (daemon reale); per questo NON
# installiamo podman-docker (collide). podman resta il default rootless.
RUN dnf -y install \
        podman buildah skopeo podman-compose \
        moby-engine \
        distrobox \
        && dnf clean all && \
    systemctl enable docker.socket podman.socket

# ─── Kubernetes: kubectl ─────────────────────────────────────────
# (helm/k9s/krew si aggiungono per-utente via mise, senza toccare l'immagine)
RUN dnf -y install kubernetes-client && dnf clean all

# ─── VM tooling: libvirt/virt-manager + quickemu (quickget) ──────
RUN dnf -y install \
        virt-manager qemu-kvm \
        libvirt-daemon-driver-qemu libvirt-client \
        quickemu \
        && dnf clean all && \
    systemctl enable libvirtd.service

# ─── mise (runtime/tool manager: node/python/go/... per-progetto) ─
RUN curl -fsSL https://mise.jdx.dev/rpm/mise.repo -o /etc/yum.repos.d/mise.repo && \
    dnf -y install mise && dnf clean all

# ─── Flatpak + Flathub (app GUI installabili senza rebuild) ──────
RUN dnf -y install flatpak && dnf clean all

# Flatpak su bootc va installato al PRIMO BOOT (/var non è nell'immagine):
# servizio oneshot che aggiunge Flathub e installa la lista default (Bazaar...).
COPY build_files/flatpaks.list /usr/share/sosharkos/flatpaks.list
COPY build_files/sosharkos-flatpak-setup.sh /usr/libexec/sosharkos-flatpak-setup
COPY build_files/sosharkos-flatpak-setup.service /usr/lib/systemd/system/sosharkos-flatpak-setup.service
RUN chmod +x /usr/libexec/sosharkos-flatpak-setup && \
    systemctl enable sosharkos-flatpak-setup.service

# ═════════════════════════════════════════════════════════════════
# Layer 4 · App neutre
# ═════════════════════════════════════════════════════════════════

# ─── 1Password (vault manager nativo, repo ufficiale) ────────────
# App neutra: l'utente fa il proprio login. Nessuna config/agent nel layer.
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc && \
    cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
RUN dnf -y install 1password 1password-cli && dnf clean all
# Bitwarden → via Flatpak al primo boot (no repo RPM ufficiale): vedi flatpaks.list

# ─── /etc/skel: defaults generici per nuovi utenti ───────────────
COPY build_files/skel/ /etc/skel/

# ─── os-release ──────────────────────────────────────────────────
RUN sed -i 's/^NAME="Fedora Linux"/NAME="SOsharkOS"/' /etc/os-release && \
    sed -i 's/^PRETTY_NAME="Fedora Linux.*"/PRETTY_NAME="SOsharkOS (CachyOS-kernel + Niri\/Noctalia)"/' /etc/os-release

# ─── Cleanup + lint ──────────────────────────────────────────────
RUN rm -rf /var/cache/* /var/log/*.log /tmp/* && \
    bootc container lint

# CLAUDE.md — SOsharkOS

Primer per riprendere il progetto da zero su **qualsiasi macchina**. Per le
*decisioni* sui pacchetti vedi [`docs/packages.md`](docs/packages.md); per i
*test* vedi [`docs/testing.md`](docs/testing.md); per le *fasi* [`ROADMAP.md`](ROADMAP.md).

## Cos'è
**Distro immutable bootc, condivisibile** (per colleghi/amici, non personale):
**Fedora bootc 44** + **kernel CachyOS** + **Niri** + **Noctalia** + greetd.
Nessuna identità/segreto nell'immagine. Pubblicazione prevista su
`ghcr.io/osharko/sosharkos` (registry sovrascrivibile via `just REGISTRY=…`).

## Filosofia: l'immagine è un *launchpad*
L'immagine (cotta in build) = **OS + package manager soltanto**: kernel, driver,
desktop, servizi, codec, e podman/docker/distrobox/flatpak/mise/virt.
**Le app vivono SOPRA**, scaricate al **primo boot**:
- Flatpak baseline non interattiva → `build_files/flatpaks.list` +
  `sosharkos-flatpak-setup.service` (Bazaar, Obsidian, MarkText, IntelliJ,
  Bottles, Blanket, Steam, MangoHud/vkBasalt extensions).
- Onboarding interattivo (gum) → `build_files/sosharkos-onboard.sh` al primo
  login: brew, mise runtime LTS (python/node/java/go/dotnet), flatpak extra,
  distrobox box. Tutto opt-out, in `/home`/`/var`, rimovibile.

> **bootc ≠ Arch/Cachy**: NON c'è `pacman -S` a install-time. L'immagine è
> pre-costruita e deployata **atomica** (upgrade/rollback con `bootc`). Per
> alleggerire (14G→10G) si sposta l'app-layer su Flatpak/onboarding, NON si
> "installa a install-time".

## Repo layout
```
Containerfile              # l'immagine (ordine layer COMMENTATO e CRITICO, vedi sotto)
Justfile                   # just build / iso / vm-up / test / test-vm / push / ci
build_files/
  flatpaks.list            # app Flatpak installate al 1° boot
  sosharkos-flatpak-setup.{sh,service}   # servizio oneshot 1° boot
  sosharkos-onboard.sh     # wizard gum 1° login (brew/mise/flatpak/distrobox)
  kickstart.ks             # install unattended (inst.ks=)
  skel/                    # /etc/skel (config niri default con autostart noctalia)
docs/
  packages.md              # SOURCE OF TRUTH delle scelte (§0–§18, checkbox)
  install.md               # install: bootc install to-disk / kickstart / upgrade
  testing.md               # piano di test completo + matrice + cosa è (im)possibile
tests/                     # suite 3-tier (vedi docs/testing.md)
ROADMAP.md
```

## Quickstart
```bash
just build      # OCI image locale sosharkos:dev (~10-15 min)
just test       # Tier 1 introspezione (no boot, secondi)
just test-vm    # render qcow2 + boot QEMU + smoke (~15 min)
just iso        # ISO installabile
just push       # → ghcr.io/osharko/sosharkos:latest (serve podman login ghcr.io)
```

## Ordine dei layer nel Containerfile — È CRITICO
1. RPM Fusion (free+nonfree+cisco-openh264)
2. **Multimedia/GPU PIENO (ffmpeg rpmfusion + mesa-*-freeworld) — PRIMA del desktop**
3. Kernel CachyOS
4. Niri / Noctalia / greetd
5. Plumbing (audio/net/bt/polkit/power/keyring)
6. Launchpad → CLI → editor/app → vault/AV → gaming/emulazione → fonts
7. Flatpak first-boot + onboarding + rootfs config + skel + os-release + `bootc lint`

## Gotcha HARD (senza questi non builda — imparati a caro prezzo)
1. **Kernel CachyOS in build container**: il `%posttrans` fa
   `kernel-install`→dracut e fallisce (`modules.dep missing`). Lo scriptlet SALTA
   se esiste `/run/ostree-booted`. Quindi: `touch /run/ostree-booted` durante
   l'install, **rimuovi il kernel stock** (`dnf remove kernel kernel-core
   kernel-modules kernel-modules-core` → altrimenti `bootc lint` fallisce
   "multiple subdirectories in usr/lib/modules"), poi rigenera l'initramfs a
   build-time: `depmod -a $KVER` + `dracut --no-hostonly --kver $KVER --add
   ostree -f /usr/lib/modules/$KVER/initramfs.img`. `KVER=$(ls /usr/lib/modules
   | grep cachyos)`.
2. **Codec PRIMA del desktop**: `dnf swap --allowerasing ffmpeg-free ffmpeg`
   eseguito DOPO il desktop fa un **cascade -346 pkg** (rimuove
   niri/noctalia/qt6-multimedia/gnome-keyring). La base F44 non ha ffmpeg/mesa →
   installa lo stack pieno SUBITO dopo RPM Fusion (install diretto, NIENTE swap).
3. **Noctalia su Fedora** = COPR `zhangyi6324/noctalia-shell` (tira `noctalia-qs`,
   build quickshell dedicata che CONFLIGGE col `quickshell` Fedora → non
   installarlo). Avvio: niri `spawn-at-startup "qs" "-c" "noctalia-shell"`.
4. **bootc-image-builder è rootful**: immagine `podman build` rootless non visibile
   → `podman save IMG | sudo podman load`; referenzia `localhost/IMG`; passa
   `--rootfs btrfs` (o l'immagine deve avere `/usr/lib/bootc/install/*.toml` con
   `[install.filesystem.root] type="btrfs"` — già presente); il qcow2 esce
   root-owned → `chown`.
5. `customizations.services` NON supportato per qcow2 in bib (sshd è già
   `enabled` nell'immagine).

## Nomi pacchetto F44 / COPR (cheatsheet)
- kernel: `kernel-cachyos` + **`kernel-cachyos-devel-matched`** (NON *-headers*) +
  `cachyos-settings` `scx-scheds` (COPR `bieszczaders/kernel-cachyos` + `-addons`)
- codec: `fdk-aac-free` (no lib), `x265`, `svt-av1`, `libavcodec-freeworld`,
  `mesa-va-drivers-freeworld`, `mesa-vulkan-drivers-freeworld`
- vm: `qemu-kvm-core` + `qemu-img` (slim, no multi-arch/edk2-aarch64/qemu-user)
- COPR: `yalter/niri`, `zhangyi6324/noctalia-shell`, `scottames/ghostty`,
  `atim/starship` (+`atim/lazygit`), `solopasha/hyprland` (hyprlock/hypridle/hyprpicker)
- NON in repo Fedora → onboarding (mise/brew): `mdcat`, `lazygit`, `lazydocker`
- nativo only (no flatpak ufficiale): `1password` (~511MB)
- ancora da pinnare COPR: `gpu-screen-recorder`, `wl-screenrec`, `gifski`
  (deps plugin Noctalia screen-recorder)

## Come estendere
- **Aggiungere un pacchetto nativo**: prima `dnf -y --assumeno install <pkg>` in
  `podman run fedora:44` con i repo/COPR abilitati (vedi pattern in cronologia),
  poi mettilo nel layer giusto del Containerfile + in `tests/expectations.sh`.
- **Aggiungere un'app GUI**: preferisci Flatpak → `build_files/flatpaks.list` (1°
  boot). Solo se non c'è flatpak → nativo.
- **Bump Fedora 44→45**: cambia `FROM …fedora-bootc:45`, poi RI-VALIDA tutti i
  nomi pacchetto/COPR con il dry-run (i COPR potrebbero non avere ancora 45) —
  vedi `docs/testing.md` § "Future-proof".
- **Nuova spin (DE diverso)**: stesso base+kernel+launchpad, cambia il layer
  desktop (es. GNOME al posto di Niri/Noctalia) → Containerfile separato o build
  arg; aggiungi una matrice di test per la spin.

## Test & CI — UN solo entrypoint (`tests/ci.sh`), zero divergenza locale↔CI
Pipeline e locale lanciano lo **stesso** script:
- `just ci` (tutto; con `/dev/kvm` anche boot/e2e/render) · `just ci-host`
  (`--no-vm`) · `just ci-vm` (`--vm-only`) · `just ci-act` (la workflow GHA in
  Docker via **act**) · `just lint-ci` (actionlint).
- `.github/workflows/build.yml`: job **build-test** (GitHub *hosted*, no KVM) =
  `ci.sh --no-vm` (build + Tier1 + per-prodotto → push GHCR); job **e2e-kvm**
  (runner **self-hosted con KVM**, opt-in `vars.HAS_KVM_RUNNER=true`) =
  `ci.sh --vm-only` (boot VM + smoke + per-prodotto-vm + integrazione k3d/k9s +
  render). I runner hosted non hanno `/dev/kvm` → i Tier2/3 vanno su self-hosted
  con label `kvm` (vedi `docs/testing.md`).
- **Test per-prodotto**: `tests/products/<nome>.yaml` (un YAML per pacchetto:
  unit headless + checklist umana) eseguiti da `run-products.sh`. Aggiungere un
  prodotto = aggiungere un YAML. 3 livelli: 🟢 headless · 🟡 grafico-QEMU · 🔴 HW reale.

### Gotcha CI (GHA hosted) — imparati a caro prezzo
- **Nome immagine COMPLETO** `localhost/sosharkos:ci` (build+run): il nome corto
  su GHA viene risolto su docker.io → "access denied".
- **`--network=none`** sui `podman run` dei test: evita il setup rete rootless
  (slirp/pasta) che altrimenti fa fallire ogni container.
- **1Password**: repo via `printf` (NO heredoc — buildah legge `[1password]`
  come istruzione se splittato), `repo_gpgcheck=0`, e **retry 5×** sull'install
  (metadata di downloads.1password.com flaky) + `rpm -q` di verifica.
- **`free-disk-space`** (jlumbroso) prima del build (immagine ~10G). NIENTE
  storage su /mnt: la storage.conf minimale rompe l'overlay rootless.
- **Cache trappola**: i build locali fanno cache-hit → un layer rotto resta
  mascherato. Per validare come il CI: build FRESH (cambiare il layer/`--no-cache`)
  o leggere i log GHA (`gh run view <id> --log-failed`). Lo step `Diagnostica`
  (always) stampa `df`+`podman images`+sanity `podman run` per la causa reale.

## Stato attuale
- Remote: **github.com/osharko/SosharkoS** (push via chiave SSH / 1Password agent;
  clonabile da qualsiasi macchina, partire da questo CLAUDE.md).
- Build VERDE **10G**, `bootc lint` ok. **Tier1 92/0**, **per-prodotto(image) 21/0**,
  **smoke VM 14/0** (docker/distrobox/kubectl/mise/flathub + decoder h264/hevc/av1/aac),
  **render desktop in QEMU validato** (niri+Noctalia, grim 1280×800). qcow2/vmdk/vpc/
  ovf/gce + boot ok.
- **CI GitHub Actions VERDE** (build-test): build + Tier1 + per-prodotto + push
  → immagine pubblicata su **ghcr.io/osharko/sosharkos** (latest + date + sha).
  Job `e2e-kvm` (Tier2/3) skippato finché non registri un runner self-hosted KVM
  + `vars.HAS_KVM_RUNNER=true`.
Backlog: audio in QEMU (routing pipewire→hda), COPR per gpu-screen-recorder/
wl-screenrec/gifski (plugin Noctalia screen-recorder), xpadneo/xone, WinBoat,
`install-to-disk` test, registrare un runner self-hosted KVM per i Tier2/3 in CI.
Dettagli e piano test onesto (cosa è automatizzabile / solo HW): `docs/testing.md`.

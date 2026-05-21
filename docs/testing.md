# SOsharkOS — piano di test (onesto)

Obiettivo: validare **ogni elemento introdotto** (unit) e il **sistema completo**
(integrazione), distinguendo con onestà cosa si automatizza, cosa richiede
display/hardware, e cosa è impensabile in CI. Pensato per essere **future-proof**
(bump Fedora 45, spin con DE diversi, nuovi pacchetti).

## I 3 livelli di validabilità

| | Livello | Dove gira | Esempi |
|---|---|---|---|
| 🟢 | **Headless-auto** | CI / `podman` / VM via SSH | presenza pacchetti, CLI funzionale, **decode** codec, container, k8s (k3d), mise, build, install-to-disk |
| 🟡 | **Grafico — QEMU-auto** | QEMU `egl-headless` + `virtio-gpu-gl` + **QMP screendump** + **audio→wav** | render niri+noctalia (screenshot non-nero), **lancio** GUI app (codium/brave), **playback A/V** (video su framebuffer + audio catturato su wav, RMS≠0). NON serve HW reale. |
| 🔴 | **Solo umano / reale** | hardware fisico / account / licenze | accel **GPU hardware** (VAAPI/Vulkan perf), gaming Proton *reale*, **gamepad** fisico, fingerprint, **1Password unlock** (account), Steam *libreria* (account), bluetooth pairing, **WinBoat** (licenza Windows), suspend/brightness laptop |

> Regola: un test 🔴 NON va forzato in CI (darebbe falsi rossi). Va in una
> **checklist umana** (sezione finale) con passi precisi e criterio di successo.

## I tier della suite (`tests/`)

| Tier | Script | Cosa | Livello |
|---|---|---|---|
| 0 | `bootc container lint` (in build) | immagine bootc valida, 1 solo kernel | 🟢 |
| 1 | `test-image.sh` (`just test`) | **presenza** pacchetti/unit/file/encoder — *unit di esistenza* | 🟢 |
| 2 | `integration.sh` (in VM via SSH) | **funzionale**: codec decode, container, k3d+k9s, distrobox, mise — *unit funzionali + integrazione* | 🟢 |
| 3 | `test-vm-gui.sh` (QEMU egl-headless+virtio-gpu+screendump+audio-wav) | **render** desktop + **playback A/V** + lancio GUI — in QEMU, no HW reale | 🟡 |
| 4 | checklist umana (sotto) | accel GPU, account (1P/Steam), licenze (WinBoat), sensori fisici | 🔴 |

`test-vm.sh` orchestra: qcow2 (bootc-image-builder) → boot QEMU → SSH → esegue
`smoke.sh`/`integration.sh`.

## Descrittori per-prodotto (`tests/products/*.yaml`)

Ogni prodotto introdotto ha **un YAML** in `tests/products/` che dichiara i suoi
test (unit + checklist umana). Il runner `tests/run-products.sh` li esegue:

```bash
just test-products                       # contesto image (headless, sull'immagine)
bash tests/run-products.sh --context vm --ssh "ssh -p 2222 …"   # nella VM
```
- `level: headless` + `context` combaciante → esegue `cmd` (auto).
- `level: display|human` → stampa la checklist (`steps`) da validare a mano.

**Aggiungere un prodotto = aggiungere un YAML** (vedi `tests/products/README.md`).
Stato attuale: 23 descrittori, contesto image **21 ✓ / 0 ✗** (gli altri sono
vm/display/human). La matrice qui sotto è la vista d'insieme; i YAML sono la fonte.

---

## Matrice per-elemento (unit test di OGNI pacchetto introdotto)

Legenda stato: ✅ validato · ✍️ scritto, da eseguire · ⬜ da scrivere.
"Cmd" = comando del test unitario.

### Codec / multimedia (§9)
| Elemento | Unit headless 🟢 | Playback 🟡/🔴 | Stato |
|---|---|---|---|
| h264 | `ffmpeg -i s.mp4 -f null -` (decode ok) + estrai 1 frame PNG non-nero | mpv su schermo + audio | ✍️ |
| HEVC/h265 | idem con sample HEVC | idem | ✍️ |
| AV1 | idem con sample AV1 | idem | ✍️ |
| AAC/audio | `ffmpeg -i s -map a -f wav out` + RMS≠0 | suono reale 🔴 | ✍️ |
| VAAPI **hardware** | `vainfo` lista profili | `ffmpeg -hwaccel vaapi` 🔴 (serve GPU reale, no in qemu) | 🔴 |

→ `tests/test-codecs.sh`: scarica sample h264/hevc/av1/aac, **decode-to-null** +
estrazione frame/audio = validazione *senza display*. Il playback percepito (video
nitido + suono) resta 🔴 umano (o 🟡 con virtio-gpu+screenshot+sink dummy).

### Container / virtualizzazione (§4/§16)
| Elemento | Unit 🟢 | Stato |
|---|---|---|
| podman | `podman run --rm hello-world` | ✍️ |
| docker (moby) | `docker run --rm hello-world` (docker.socket) | ✍️ |
| distrobox | `distrobox create -i fedora:latest t && distrobox enter t -- echo ok` | ✍️ |
| lazydocker | `lazydocker --version` (TUI completo 🟡 expect/umano) | ✍️ |
| virt-manager/qemu | `qemu-system-x86_64 --version`; VM nested 🟡 | ✍️ |
| quickemu | `quickget --version`; download VM 🟡 (rete/tempo) | ✍️ |
| Bottles/Wine | flatpak `com.usebottles.bottles` lancia 🟡 | 🔴/🟡 |
| WinBoat | scarica Windows + nested KVM | 🔴 |

### Kubernetes (§4)
| Elemento | Unit 🟢 | Stato |
|---|---|---|
| kubectl | `kubectl version --client` | ✅ |
| cluster | **k3d**/kind: cluster in docker → `kubectl get nodes` Ready | ✍️ |
| k9s | `k9s info` (non-interattivo); TUI 🟡 | ✍️ |
| helm/k9s/krew | via mise per-utente | ⬜ |

> k3s "puro" su immutable scrive in /usr/local + systemd: scomodo. **k3d**
> (k3s-in-docker) o **kind** girano nel docker/podman già presenti → la via
> immutable-friendly. Si installano via mise/brew (onboarding) o si testano on-demand.

### Dev runtime (§17 onboarding)
| Elemento | Unit 🟢 | Stato |
|---|---|---|
| mise | `mise --version` + `mise use -g node@lts && node --version` | ✍️ |
| brew | `brew --version` dopo bootstrap (in /home) | ✍️ |
| direnv | `direnv --version` | ✍️ |

### Editor / app GUI (§12)
| Elemento | Presenza 🟢 | Apertura progetto 🟡/🔴 | Stato |
|---|---|---|---|
| VSCodium | `codium --version` | `codium <dir>` render+finestra → screenshot | 🟡 |
| IntelliJ (flatpak) | flatpak info | apre progetto (pesante) → screenshot/umano | 🟡/🔴 |
| Brave | `brave-browser --version` | apre URL → screenshot | 🟡 |
| Obsidian/MarkText | flatpak info | apre .md → 🟡 | 🟡 |

→ scenario utente "clone repo via ssh + apri in vscode/intellij": la parte
*presenza+CLI* è 🟢; l'*apertura con render* è 🟡 (VM con virtio-gpu + sessione
wayland + screenshot, o validazione umana su HW reale).

### Desktop (§1/§11)
| Elemento | Unit 🟢 | Render 🟡/🔴 | Stato |
|---|---|---|---|
| niri | `niri validate -c config.kdl` | niri parte + mostra | 🟡 |
| noctalia | `command -v qs` | bar/launcher visibili → screenshot | 🟡 |
| hyprlock/hypridle | `--version` | lock reale | 🟡 |

### Gaming (§7/§15)
| Elemento | Unit 🟢 | Reale 🔴 | Stato |
|---|---|---|---|
| gamemode | `gamemoded --version` | boost in gioco | ✍️/🔴 |
| mangohud (flatpak ext) | flatpak info extension | overlay in gioco | 🔴 |
| Steam (flatpak) | flatpak info | login + Proton game | 🔴 |
| controller xpadneo/xone | modulo presente | input fisico | 🔴 |

### Vault / security (§5/§6)
| Elemento | Unit 🟢 | Reale 🔴 | Stato |
|---|---|---|---|
| 1Password | `1password --version` | unlock account | 🔴 |
| ClamAV | `clamscan --version` + scan EICAR test file → rileva | ✍️ |
| rkhunter | `rkhunter --version` + `--check` dry | ✍️ |

### Fonts (§14)
| Elemento | Unit 🟢 | Stato |
|---|---|---|
| nerd/cascadia/jetbrains/noto | `fc-list | grep -i <font>` | ✍️ |

---

## Test di integrazione (sistema con tutto insieme)

Scenari composti, eseguiti in VM (`integration.sh`):
1. **Container+k8s+TUI**: docker run → k3d cluster up → `kubectl get nodes` Ready
   → `k9s info` legge il cluster → `lazydocker --version` vede i container k3d. 🟢
2. **Media pipeline**: scarica sample HEVC+AV1 → decode-to-null ok → estrai frame
   PNG (non-nero) + audio WAV (RMS≠0). 🟢 (playback percepito 🔴)
3. **Dev loop**: clone *questo* repo via SSH → `mise use node@lts` →
   `codium --version`/apri (🟡) → build di un progetto di prova. 🟢/🟡
4. **Install reale**: `bootc install to-disk` su un file-disk loopback → verifica
   partizioni/btrfs + bootloader. 🟢
5. **Primo boot**: il `sosharkos-flatpak-setup.service` installa la baseline (già
   visto: flathub presente) → `flatpak list` contiene Bazaar ecc. 🟢
6. **Desktop end-to-end** (🟡): VM virtio-gpu → greetd→niri→noctalia → screenshot
   con la bar visibile.

---

## Action plan — come portare i test a 100%

### Claude (automatizzabile, prossime iterazioni)
- [ ] `tests/test-codecs.sh`: download sample (Big Buck Bunny h264/hevc/av1 +
      aac) → decode-to-null + frame/audio extract. Eseguire in VM.
- [ ] `tests/integration.sh`: container+k3d+k9s+distrobox+mise+clamav(EICAR).
- [ ] Rendere `smoke.sh` robusto: attesa `is-system-running` (loop), retry
      `docker run`, check codec via `ffmpeg -decoders`, check noctalia via `qs`.
- [ ] `tests/install-to-disk.sh`: `bootc install to-disk` su loopback + verifica.
- [ ] `tests/gui-smoke.sh` (🟡): VM con `-device virtio-gpu` + sessione wayland +
      `grim` screenshot; assert finestra codium/brave (titolo via `niri msg` o OCR).
- [ ] CI GHA: Tier 0+1 ad ogni push; Tier 2 nightly su runner con KVM.

### Umano (🔴, su hardware reale — checklist con criterio di successo)
- [ ] **A/V playback**: `mpv sample-hevc.mkv` → video fluido + audio udibile.
- [ ] **VAAPI HW**: `vainfo` mostra profili; `mpv --hwdec=vaapi` usa la GPU (`intel_gpu_top`/`radeontop`).
- [ ] **Gaming**: Steam (flatpak) → login → un gioco parte con Proton; MangoHud overlay; `gamemoded` attivo.
- [ ] **Controller**: collega un pad → `evtest` lo vede → input in gioco.
- [ ] **1Password**: unlock con account → SSH agent funziona.
- [ ] **Bluetooth**: pairing di un device.
- [ ] **Desktop UX**: login greetd → niri+noctalia usabili (bar, launcher, lock, screenshot).
- [ ] **WinBoat**: primo run scarica Windows (nested KVM) → un'app Windows come finestra nativa.
- [ ] **Fingerprint/suspend/brightness** (se su laptop).

---

## Future-proof (Fedora 45, nuove spin, nuovi pacchetti)
1. **Bump Fedora**: cambia `FROM …:45`, poi **ri-esegui il dry-run di risoluzione**
   (i COPR potrebbero non avere ancora 45 — kernel/niri/noctalia/ghostty). Pattern:
   `podman run fedora:45` con tutti i repo/COPR + `dnf install --assumeno <lista>`
   → becca i nomi/COPR mancanti in un colpo (così abbiamo trovato i bug F44).
2. **Aggiorna `tests/expectations.sh`** con ogni pacchetto nuovo/rinominato → il
   Tier 1 diventa la rete di sicurezza dei rinomini.
3. **Nuova spin (DE diverso)**: stessa base+kernel+launchpad, layer desktop
   diverso → matrice di test parametrizzata per spin (presence + render).
4. Ogni elemento nuovo: aggiungi **una riga nella matrice** qui + il check in
   `expectations.sh` (unit) e, se sensato, in `integration.sh`.

## Stato corrente dei test
- Tier 0 `bootc lint`: ✅ · Tier 1 `test-image.sh`: ✅ **92/0** · per-prodotto
  (image): ✅ **21/0**
- Tier 2 `test-vm.sh` → `smoke.sh`: ✅ **14✓/4!/0✗** (boot + SSH + docker +
  distrobox + kubectl + mise + flathub + decoder h264/hevc/av1/aac; i WARN sono
  bluetooth/libvirtd/pipewire-user/vainfo, attesi in VM headless)
- **Tier 3 grafico `test-vm-gui.sh`: ✅ render desktop VALIDATO in QEMU** —
  niri+Noctalia renderizzano (grim 1280×800, screenshot reale), `bootc lint` ok.
  Audio QEMU = WARN (routing pipewire→hda da rifinire; audio reale su HW).
  *Bug REALI scoperti da questo tier:* greeter user inesistente (→ tuigreet),
  test-user senza sudo (→ password+NOPASSWD).
- ⬜ da creare: `integration.sh` esecuzione in VM (k3d/k9s), `install-to-disk.sh`

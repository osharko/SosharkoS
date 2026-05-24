# Roadmap SOsharkOS

Ordine suggerito, non vincolante. Obiettivo finale: un'immagine immutabile
**condivisibile** (colleghi/amici) = base Fedora+CachyOS+Niri/Noctalia con un
launchpad di strumenti, su cui ognuno installa il proprio stack senza rebuild.

---

## Fase 0 — Bootstrap — _in corso_

Avere un'immagine OCI che boota in VM e mostra Niri+Noctalia.

- [x] Repo iniziale (`Containerfile`, `Justfile`, `.github/workflows`, `README`)
- [ ] `just build` — primo build OCI verde
- [ ] `just iso` — ISO generato da bootc-image-builder senza errori
- [ ] `just vm-up` — VM si avvia, install completa
- [ ] Primo login: greetd → niri-session → Noctalia visibile

**DoD:** la VM mostra il bar di Noctalia su una sessione Niri.

## Fase 1 — Launchpad validation

Verificare che gli strumenti "per installare tutto il resto" funzionino nell'image.

- [ ] **distrobox**: `distrobox create` + `enter` ok (podman rootless)
- [ ] **docker** (moby): `docker run hello-world` (docker.socket attivo)
- [ ] **podman**: build + run rootless
- [ ] **kubectl**: presente e versionato
- [ ] **VM**: `quickget` scarica una ISO + `quickemu` la avvia; virt-manager apre
- [ ] **mise**: `mise use node@lts` in una dir di test
- [ ] **Flatpak first-boot**: `sosharkos-flatpak-setup.service` installa Bazaar +
      Bitwarden da Flathub al primo avvio (marker `/var/lib/sosharkos/...`)
- [ ] **1Password** nativo: si avvia da Niri, login utente ok

**DoD:** da una VM fresca, ognuno degli strumenti sopra fa la sua "prima
installazione" di qualcosa senza toccare l'immagine.

## Fase 2 — First-boot UX & default sani

Rendere l'esperienza out-of-box buona per chi non sei tu.

- [ ] Default Niri/Noctalia ragionevoli in `/etc/skel` (niente identità personale)
- [ ] Greeter/login chiaro; tastiera/locale selezionabili in install
- [ ] `flatpaks.list` rivisto (cosa ha senso pre-installare vs lasciare a Bazaar)
- [ ] Primo-boot: messaggio/onboarding minimale ("come installo le mie app")
- [ ] Verifica che nessun segreto/identità sia finito nell'immagine

**DoD:** un collega installa l'ISO e in <10 min ha desktop usabile + sa dove
installare le sue cose (Bazaar, distrobox, mise).

## Fase 3 — CI pipeline matura

Build automatico stabile + immagine firmata.

- [ ] GHA: build verificato su ogni push
- [ ] Cron daily: push su GHCR `:latest` + `:YYYYMMDD`
- [ ] Tag semver per release (`:v0.1.0`, …)
- [ ] cosign signing dell'immagine (chain of trust per chi fa `bootc upgrade`)
- [ ] Renovate/Dependabot: bump COPR kernel / niri / pacchetti major

**DoD:** push su main → ~20 min → image firmata su GHCR; cron mattutino ribilda
su upstream fresco.

## Fase 4 — Distribuzione

Renderla davvero condivisibile.

- [ ] ISO di release scaricabile (GitHub Releases)
- [ ] `docs/install.md`: installare l'ISO + `bootc upgrade` + rollback
- [ ] `docs/customize.md`: distrobox, mise, Bazaar, "porta i tuoi dotfile"
- [ ] README con quickstart per chi riceve l'immagine
- [ ] (opzionale) registrare come spin community se c'è richiesta

**DoD:** una persona esterna installa SOsharkOS da zero seguendo solo i docs.

## Backlog / future ideas

- [x] **Waydroid + androidbox** (Android in container LXC, app come finestre
      native su Niri) — pacchetto nell'immagine (base Fedora 44, binder built-in
      nel kernel CachyOS); UX a livello OS con `androidbox-start/stop/status`,
      container service DISABILITATO di default (opt-in persistente via systemd
      enable), user session unit per il login grafico, multi-window. Primo
      `androidbox-start` esegue `waydroid init -s GAPPS`; certificazione Play
      Store a runtime. **Cartelle condivise host↔Android** (`androidbox-share`/
      `androidbox-unshare`): bind-mount config-driven legati al lifecycle (default
      dagli XDG dir → Pictures/Download/Music/Documents/Movies), rescan MediaStore
      no-restart, DATADIR user/system rilevata dinamicamente (§16).
- [x] **BoxBuddy** (GUI distrobox manager) — flatpak al 1° boot (§4).
- [ ] **Doppia ISO**: secondo desktop oltre a Niri/Noctalia (es. GNOME) —
      stesso base+kernel+launchpad, DE diverso
- [ ] Containerfile multi-arch (aarch64 oltre x86_64)
- [ ] Plymouth boot splash custom (cosmetico)
- [ ] Test bench: nightly install in VM + smoke test (boot, niri, noctalia,
      docker/distrobox/quickemu smoke)
- [ ] `helm`/`k9s`/`krew` come default mise globale opzionale
- [ ] Variante "server/headless" senza DE (solo launchpad) se serve

# Installare SOsharkOS

> **Modello bootc**: l'artefatto primario è l'**immagine OCI** su
> `ghcr.io/osharko/sosharkos:latest` (come Silverblue). L'**ISO non è il
> prodotto: si genera dall'immagine**. Puoi installare *senza* ISO
> (`bootc install to-disk`, §1) o *con* ISO (§2/§3).

## Dove scaricare l'ISO

> **L'ISO è ~5.5 GB → NON sta negli asset di GitHub Release** (limite 2 GB/file).
> Modello (tipo *omarchy*): la **Release** porta solo le **note/changelog + il
> link** al file; il **file ISO è ospitato fuori** (Google Drive). La pipeline
> serve solo a *produrre* l'ISO, non a distribuirla.

- **Produrre l'ISO (CI, on-demand)**: GitHub → *Actions* → workflow *"Build, test
  & push"* → **Run workflow** → a fine run scarichi l'artifact **`sosharkos-iso`**
  (job `iso`, da immagine OCI con bootc-image-builder — non serve KVM). Da CLI:
  `gh run download <run-id> -n sosharkos-iso`.
- **Distribuire (manuale)**: carica `install.iso` su **Google Drive**, poi crea
  una **GitHub Release** (tag `vX.Y.Z`) con il **changelog** e il **link al
  Drive**. Niente file negli asset.
- **In locale**: `just iso` → `output/bootiso/install.iso`.

> 💡 La via "vera" bootc spesso **non richiede ISO**: installa direttamente
> dall'immagine OCI con `bootc install to-disk` (§1). L'ISO serve solo per una
> chiavetta bootabile / installer Anaconda.

Tutti installano poi l'immagine bootc e si aggiornano con `bootc upgrade`
(rollback istantaneo).

## 1. Da cmdline, fully scriptable — `bootc install to-disk` (§18)

La via più "quickget-like": da un live env (o dall'immagine stessa come
container privilegiato), zero GUI, argomenti preimpostati.

```bash
# Su un disco target /dev/sdX (ATTENZIONE: lo cancella)
sudo podman run --rm --privileged --pid=host \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  --security-opt label=type:unconfined_t \
  ghcr.io/osharko/sosharkos:latest \
  bootc install to-disk --filesystem btrfs --wipe /dev/sdX
```

Opzioni utili: `--filesystem btrfs|xfs|ext4`, `--root-ssh-authorized-keys <file>`,
`--karg ...`. Vedi `bootc install to-disk --help`.

## 2. ISO unattended — Kickstart (§18)

Build di un'ISO installabile e install senza interazione:

```bash
just iso                         # genera output/bootiso/install.iso
```

Avvia l'ISO e passa il kickstart: alla riga di boot aggiungi
`inst.ks=<url|path>` puntando a [`build_files/kickstart.ks`](../build_files/kickstart.ks)
(personalizza disco/utente/locale). Install completamente automatica.

## 3. ISO interattiva (Anaconda GUI)

```bash
just iso && just vm-up           # prova in VM
```
Boota l'ISO, segui Anaconda (disco, utente, locale), reboot.

## Dopo l'install

```bash
# aggiornamento atomico all'ultima immagine pubblicata
sudo bootc upgrade --apply

# rollback all'immagine precedente (istantaneo, al reboot)
sudo bootc rollback

# passare a un'altra immagine/tag
sudo bootc switch ghcr.io/osharko/sosharkos:vX.Y.Z

# stato
bootc status
```

## Primo login

Al primo login interattivo parte l'**onboarding** (`sosharkos-onboard`): scegli
cosa installare via mise/brew/flatpak/distrobox — tutto in `/home`, fuori
dall'immutabile, rimovibile. Rilanciabile con `sosharkos-onboard --force`.

> App GUI aggiuntive: usa **Bazaar** (store Flatpak) già installato.

# Installare SOsharkOS

Tre modi, dal più automatico al più manuale. Tutti installano l'immagine bootc
(`ghcr.io/osharko/sosharkos:latest`) e poi si aggiorna atomicamente con
`bootc upgrade` (rollback istantaneo).

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

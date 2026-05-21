# SOsharkOS — test automatici

Tre livelli, dal più veloce/deterministico al più realistico. Niente più check
manuali: il rosso/verde dei test è la specifica eseguibile della distro.

| Tier | Script | Boot? | Cosa verifica | Quando |
|---|---|---|---|---|
| **1 · introspezione** | `test-image.sh` | no | pacchetti, unit `enabled`, file, codec, `flatpaks.list`, `bootc lint` | ogni build / CI |
| **2/3 · VM** | `test-vm.sh` → `smoke.sh` | sì (QEMU) | la VM avvia, servizi su, runtime funzionano (docker/kubectl/codec…) | locale / nightly |

## Uso

```bash
just build          # costruisce sosharkos:dev
just test           # Tier 1 (secondi)
just test-vm        # Tier 2/3 (qcow2 + QEMU + smoke via ssh, minuti)
just ci             # build + test (gate locale)
```

Oppure diretto: `bash tests/test-image.sh sosharkos:dev`.

## Come funziona

- **`expectations.sh`** — *single source of truth*: liste di binari/RPM/unit/file
  attesi. **Tienilo allineato a `docs/packages.md`.** Aggiungi una voce qui →
  il test la pretende.
- **`test-image.sh`** — esegue comandi *dentro* l'immagine via
  `podman run --entrypoint "" IMAGE bash -lc …` (nessun boot): `command -v`,
  `rpm -q`, `systemctl is-enabled`, `test -e`, encoder ffmpeg.
- **`smoke.sh`** — check *funzionali* da eseguire nel sistema avviato
  (lo lancia `test-vm.sh` via ssh; eseguibile anche a mano post-install).
- **`test-vm.sh`** — genera qcow2 con `bootc-image-builder` (utente `tester` +
  chiave ssh effimera + sshd), avvia QEMU headless con port-forward, attende
  l'ssh, lancia `smoke.sh`, spegne. Log seriale in `tests/.tmp/serial.log`.

## Note

- **La spec è "avanti" sull'implementazione**: finché il Containerfile non
  applica §8–§15 di `packages.md`, i relativi check di Tier 1 falliscono — è il
  comportamento voluto (diventano verdi man mano che implementiamo).
- Tier 2/3 richiede `/dev/kvm`. Alcuni check (VAAPI/GPU, sessione grafica niri)
  in VM senza GPU passthrough escono `WARN`, non `FAIL`.
- CI: il job `build` può chiamare `just test` (Tier 1) dopo la build. Tier 2/3
  va su runner con KVM (nightly) o in locale.

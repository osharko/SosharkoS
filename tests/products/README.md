# tests/products — descrittori per-prodotto

Un file YAML per prodotto/pacchetto introdotto. Eseguiti da `../run-products.sh`.
Aggiungere un prodotto = aggiungere un YAML (future-proof).

## Schema
```yaml
product: <nome>
summary: <una riga>
category: codec|container|k8s|dev|editor|desktop|gaming|vault|security|font|vm|emulation
package: <rpm>        # opz.
binary:  <bin>        # opz.
flatpak: <app-id>     # opz. (installato al 1° boot)
tests:
  - name: <descrizione>
    level: headless|display|human     # headless=automatico; display/human=checklist
    context: image|vm                 # image=podman sull'immagine; vm=via ssh nella VM
    cmd: <bash; exit 0 = pass>        # per headless
    steps: |                          # per display/human: istruzioni + criterio
      ...
```
Livelli: 🟢 headless (auto) · 🟡 display (serve sessione grafica) · 🔴 human (HW reale).

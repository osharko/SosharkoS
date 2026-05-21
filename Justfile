# SOsharkOS — Justfile (https://github.com/casey/just)
#
# Loop di sviluppo locale: build OCI → genera ISO → spinge VM in virt-manager.
# Nessun bisogno di GHCR per testare; solo per pubblicare.
#
# Prerequisiti host:
#   sudo dnf -y install just podman virt-install virt-manager libvirt
#   sudo systemctl enable --now libvirtd
#   sudo usermod -aG libvirt $USER  (poi logout+login)

IMAGE_NAME := "sosharkos"
IMAGE_TAG := "dev"
ISO_OUTDIR := "output"
VM_NAME := "sosharkos-test"
VM_RAM := "4096"
VM_VCPUS := "2"
VM_DISK_GB := "40"
# Registry di pubblicazione e utente VM — sovrascrivibili:
#   just REGISTRY=ghcr.io/tuonome push
#   just VM_USER=tuonome vm-ssh
REGISTRY := "ghcr.io/osharko"
VM_USER := "osharko"

# Default: lista i target
default:
    @just --list

# Build OCI image locale con podman (~10-15 min al primo giro, poi cached)
build:
    podman build -t {{IMAGE_NAME}}:{{IMAGE_TAG}} .

# Verifica che l'immagine sia bootc-valida
lint:
    podman run --rm {{IMAGE_NAME}}:{{IMAGE_TAG}} bootc container lint

# Genera ISO bootable (Anaconda installer + tua image)
iso:
    mkdir -p {{ISO_OUTDIR}}
    sudo podman run --rm -it --privileged \
        --security-opt label=type:unconfined_t \
        -v ./{{ISO_OUTDIR}}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type iso \
        --rootfs btrfs \
        --local \
        {{IMAGE_NAME}}:{{IMAGE_TAG}}

# Avvia VM in virt-manager dall'ISO appena generato
vm-up:
    @test -f {{ISO_OUTDIR}}/bootiso/install.iso || (echo "ISO mancante — esegui 'just iso' prima" && exit 1)
    sudo virt-install \
        --name {{VM_NAME}} \
        --ram {{VM_RAM}} --vcpus {{VM_VCPUS}} \
        --disk size={{VM_DISK_GB}},format=qcow2,bus=virtio \
        --os-variant fedora42 \
        --network default \
        --graphics spice \
        --cdrom $(pwd)/{{ISO_OUTDIR}}/bootiso/install.iso \
        --noautoconsole
    virt-manager --connect qemu:///system --show-domain-console {{VM_NAME}} &

# SSH dentro la VM (richiede sshd attivo nella VM)
vm-ssh:
    @VM_IP=$(sudo virsh domifaddr {{VM_NAME}} --source agent 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1); \
    if [ -z "$VM_IP" ]; then echo "VM non trovata o agent off"; exit 1; fi; \
    ssh -o StrictHostKeyChecking=no {{VM_USER}}@$VM_IP

# Boot c switch: aggiorna VM esistente alla nuova image senza reinstallare
# (usabile solo se VM è già installata, non da ISO fresh)
vm-update:
    @echo "Esegui dentro la VM:"
    @echo "    sudo bootc switch --transport containers-storage localhost/{{IMAGE_NAME}}:{{IMAGE_TAG}}"
    @echo "    sudo bootc upgrade --apply"

# Distrugge VM di test (per ripartire pulito)
vm-clean:
    -sudo virsh destroy {{VM_NAME}} 2>/dev/null
    -sudo virsh undefine {{VM_NAME}} --remove-all-storage 2>/dev/null
    @echo "VM {{VM_NAME}} distrutta"

# Full cycle: build → iso → vm-up
cycle: build iso vm-up

# Loop veloce: solo se cambiamenti minori; rebuild image, switch VM esistente
quick: build
    @echo "Build done. Per testare, dentro VM running:"
    @echo "  sudo bootc switch --transport containers-storage localhost/{{IMAGE_NAME}}:{{IMAGE_TAG}}"

# Cleanup totale: image + ISO + VM
clean: vm-clean
    -podman rmi {{IMAGE_NAME}}:{{IMAGE_TAG}}
    -rm -rf {{ISO_OUTDIR}}

# Push image su GHCR (richiede `podman login ghcr.io` prima)
push tag="latest":
    podman tag {{IMAGE_NAME}}:{{IMAGE_TAG}} {{REGISTRY}}/{{IMAGE_NAME}}:{{tag}}
    podman push {{REGISTRY}}/{{IMAGE_NAME}}:{{tag}}

# Mostra dimensione image finale
size:
    @podman images {{IMAGE_NAME}}:{{IMAGE_TAG}} --format "table {{{{.Repository}}}}:{{{{.Tag}}}}\t{{{{.Size}}}}"

# Inspect layers (utile per ottimizzare l'image size)
layers:
    podman history {{IMAGE_NAME}}:{{IMAGE_TAG}} --no-trunc

# ─── Test ────────────────────────────────────────────────────────
# Tier 1: introspezione immagine (no boot) — veloce, CI-friendly
test:
    bash tests/test-image.sh {{IMAGE_NAME}}:{{IMAGE_TAG}}

# Tier 2/3: build qcow2 → boot QEMU headless → smoke funzionale via SSH
test-vm:
    bash tests/test-vm.sh {{IMAGE_NAME}}:{{IMAGE_TAG}}

# Gate locale completo: build + introspezione
ci: build test

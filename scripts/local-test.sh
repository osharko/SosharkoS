#!/usr/bin/env bash
# Wrapper di `just cycle` per chi non ha just installato.
# Eseguibile da VS Code task o terminal.
#
# Uso: ./scripts/local-test.sh [build|iso|vm|cycle|clean]

set -euo pipefail

cd "$(dirname "$0")/.."

ACTION="${1:-cycle}"

if command -v just >/dev/null 2>&1; then
    just "$ACTION"
    exit 0
fi

echo "→ just non trovato, uso fallback nativo per: $ACTION"

case "$ACTION" in
    build)
        podman build -t sosharkos:dev .
        ;;
    iso)
        mkdir -p output
        sudo podman run --rm -it --privileged \
            --security-opt label=type:unconfined_t \
            -v ./output:/output \
            -v /var/lib/containers/storage:/var/lib/containers/storage \
            quay.io/centos-bootc/bootc-image-builder:latest \
            --type iso --rootfs btrfs --local \
            sosharkos:dev
        ;;
    vm)
        test -f output/bootiso/install.iso || { echo "manca ISO"; exit 1; }
        sudo virt-install \
            --name sosharkos-test --ram 4096 --vcpus 2 \
            --disk size=40,format=qcow2 \
            --os-variant fedora42 \
            --graphics spice \
            --cdrom "$(pwd)/output/bootiso/install.iso" \
            --noautoconsole
        ;;
    cycle)
        "$0" build
        "$0" iso
        "$0" vm
        ;;
    clean)
        sudo virsh destroy sosharkos-test 2>/dev/null || true
        sudo virsh undefine sosharkos-test --remove-all-storage 2>/dev/null || true
        podman rmi sosharkos:dev 2>/dev/null || true
        rm -rf output/
        ;;
    *)
        echo "Uso: $0 [build|iso|vm|cycle|clean]" >&2
        exit 1
        ;;
esac

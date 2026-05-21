# SOsharkOS — Kickstart d'esempio per install UNATTENDED (§18).
# Uso: al boot dell'ISO aggiungi  inst.ks=<url|path>  (es. inst.ks=hd:LABEL=...:/ks.cfg
# o inst.ks=https://.../kickstart.ks). Personalizza disco/utente/locale e basta.
#
# NB: installa l'immagine bootc via 'ostreecontainer' (no pacchetti Anaconda).

text
lang en_US.UTF-8
keyboard --xlayouts=it
timezone Europe/Rome --utc
# Niente root login: si usa l'utente sotto
rootpw --lock

# Disco intero, partizionamento automatico btrfs (cambia 'vda' col tuo device)
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs --noswap

# Sorgente: l'immagine bootc pubblicata (cambia registry/tag)
ostreecontainer --url=ghcr.io/osharko/sosharkos:latest --no-signature-verification

# Utente iniziale (cambia nome/password; o usa --iscrypted con un hash)
user --name=user --groups=wheel --password=changeme --plaintext

# Bootloader + reboot a fine install
bootloader --timeout=1
reboot

%post --erroronfail
# l'onboarding (brew/mise/flatpak) parte al primo login dell'utente, non qui:
# resta tutto in /home, fuori dall'immutabile.
%end

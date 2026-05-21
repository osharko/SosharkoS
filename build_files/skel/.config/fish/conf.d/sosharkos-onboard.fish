# Lancia l'onboarding SOsharkOS al primo login interattivo (una volta sola).
# Dopo il marker (~/.local/state/sosharkos/onboarded) non riparte.
if status is-interactive
    and not test -f "$HOME/.local/state/sosharkos/onboarded"
    and command -q sosharkos-onboard
    sosharkos-onboard
end

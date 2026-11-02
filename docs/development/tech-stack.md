# Technology

Nix/Caisson flake, native xbps-create/xbps-rindex artifacts and repository data,
and a pinned shared impurifier core for Python/Nix activation. runit is the
default host backend; explicit systemd/OpenRC declarations select those protocols.
Native package callbacks provide reconciliation; there is no invented general
XBPS file-trigger mechanism.

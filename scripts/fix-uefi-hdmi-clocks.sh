#!/usr/bin/env bash
# Adapt the EDK2 legacy HDMI clock binding to the vendor 6.1 binding.
# Input may be a copy of /sys/firmware/fdt from a working headless boot.
# This creates a DTB only; it does not install files or change boot settings.
set -euo pipefail

if [[ $# != 2 || "$1" == "$2" ]]; then
  echo "Usage: $0 INPUT.dtb OUTPUT.dtb (different paths)" >&2
  exit 1
fi
for command in fdtget fdtput; do
  command -v "$command" >/dev/null
done
if [[ -e "$2" ]]; then
  echo "Output already exists: $2" >&2
  exit 1
fi

temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
cp -- "$1" "$temporary"

# EFI memory-map pointers and boot arguments belong to the current boot.
# The EFI stub must regenerate these on the next boot.
if fdtget -p "$temporary" /chosen >/dev/null 2>&1; then
  fdtput -r "$temporary" /chosen
fi

for index in 0 1; do
  if [[ "$index" == 0 ]]; then
    phy=/hdmiphy@fed60000
    hdmi=/hdmi@fde80000
  else
    phy=/hdmiphy@fed70000
    hdmi=/hdmi@fdea0000
  fi
  handle=$(fdtget -t x "$temporary" "$phy/clk-port" phandle)
  fdtput -r "$temporary" "$phy/clk-port"
  fdtput -t x "$temporary" "$phy" phandle "$handle"
  fdtput -t x "$temporary" "$phy" '#clock-cells' 0
  fdtput -t s "$temporary" "$phy" clock-output-names "clk_hdmiphy_pixel$index"
  fdtput -t x "$temporary" "$hdmi" phys "$handle"
done

cp -- "$temporary" "$2"

#!/bin/sh
# Utility to check IPv6 PD prefixes and device addresses for MAC 88:c9:b3:b0:76:8e
. /usr/lib/ddns/dynamic_dns_functions.sh

collect_ipv6_pd_prefixes PD
printf "PD prefixes: %s\n" "$PD"

echo "\nNeighbor addresses for MAC 88:c9:b3:b0:76:8e on br-lan:" 
ip -6 neigh show dev br-lan | grep -i 88:c9:b3:b0:76:8e || true

echo "\nCheck each neighbor address if it matches PD prefixes:" 
for a in $(ip -6 neigh show dev br-lan | awk '/88:c9:b3:b0:76:8e/ {raw=$1; sub(/%.*/, "", raw); print raw}'); do
  printf "ADDR: %s -> " "$a"
  if ipv6_address_matches_prefixes "$a" "$PD"; then
    echo "MATCH"
  else
    echo "NO"
  fi
done

# Try get_device_ipv6_address preferring PD prefixes
SEL="$(get_device_ipv6_address br-lan 88:c9:b3:b0:76:8e "$PD" 2>/dev/null || true)"
printf "\nget_device_ipv6_address (with PD): %s\n" "$SEL"

# Try select_ipv6_pd_address_from_device
select_ipv6_pd_address_from_device SEL2 br-lan "$PD" 2>/dev/null || true
printf "select_ipv6_pd_address_from_device -> %s\n" "$SEL2"

# Show interface addresses
echo "\nIP addresses (br-lan):"
ip -j -6 addr show dev br-lan

echo "\nNeighbor table (br-lan):"
ip -6 neigh show dev br-lan

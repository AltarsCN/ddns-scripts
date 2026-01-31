#!/bin/sh
# /usr/lib/ddns/dynamic_dns_lucihelper.sh
#
#.Distributed under the terms of the GNU General Public License (GPL) version 2.0
#.2014-2018 Christian Schoenebeck <christian dot schoenebeck at gmail dot com>
# This script is used by luci-app-ddns
#
# variables in small chars are read from /etc/config/ddns as parameter given here
# variables in big chars are defined inside these scripts as gloval vars
# variables in big chars beginning with "__" are local defined inside functions only
# set -vx  	#script debugger

. /usr/lib/ddns/dynamic_dns_functions.sh	# global vars are also defined here

usage() {
	cat << EOF

Usage:
 $MYPROG [options] -- command

Commands:
 get_local_ip        using given INTERFACE or NETWORK or SCRIPT or URL
 get_registered_ip   for given FQDN
 verify_dns          given DNS-SERVER
 verify_proxy        given PROXY
 start               start given SECTION
 reload              force running ddns processes to reload changed configuration
 restart             restart all ddns processes
 stop                stop given SECTION
 list_neighbors      list IPv6 neighbors for given INTERFACE/NETWORK

Parameters:
 -6                  => use_ipv6=1          (default 0)
 -d DNS-SERVER       => dns_server=SERVER[:PORT]
 -f                  => force_ipversion=1   (default 0)
 -g                  => is_glue=1           (default 0)
 -i INTERFACE        => ip_interface=INTERFACE; ip_source="interface"
 -l FQDN             => lookup_host=FQDN
 -n NETWORK          => ip_network=NETWORK; ip_source="network"
 -p PROXY            => proxy=[USER:PASS@]PROXY:PORT
 -s SCRIPT           => ip_script=SCRIPT; ip_source="script"
 -t                  => force_dnstcp=1      (default 0)
 -u URL              => ip_url=URL; ip_source="web"
 -M IDENT            => ip_device=IDENT (MAC/hostname/IPv4/DUID for target device)
 -T TYPE             => ip_device_type=TYPE (auto/mac/hostname/ipv4/duid)
 -P                  => ip_source="prefix" (IPv6 PD)
 -D                  => ip_source="dhcpv6" (DHCPv6 address)
 -A                  => ip_source="slaac" (SLAAC address)
 -E                  => ip_source="eui64" (EUI-64 address)
 -x SUFFIX           => ip_prefix_suffix=SUFFIX (for prefix source)
 -S SECTION          SECTION to [start|stop]

 -h                  => show this help and exit
 -L                  => use_logfile=1    (default 0)
 -v LEVEL            => VERBOSE=LEVEL    (default 0)
 -V                  => show version and exit

EOF
}

usage_err() {
	printf %s\\n "$MYPROG: $@" >&2
	usage >&2
	exit 255
}

record_hostname_for_mac() {
	local __MAC="$1"
	local __NAME="$2"
	local __KEY __CURRENT

	[ -n "$__MAC" ] || return 0
	[ -n "$__NAME" ] || return 0

	__MAC=$(printf "%s" "$__MAC" | tr 'A-Z' 'a-z')
	__NAME=$(printf "%s" "$__NAME" | tr -d '\r')
	[ -n "$__NAME" ] || return 0

	__KEY=${__MAC//:/_}
	eval __CURRENT="\${neighbor_name_$__KEY}"
	[ -n "$__CURRENT" ] && return 0
	eval neighbor_name_$__KEY="\"$__NAME\""
	return 0
}

duid_to_mac() {
	local __DUID="$1"
	local __CLEAN __LEN __TYPE __OFFSET __HWTYPE __MACHEX

	[ -n "$__DUID" ] || return 1

	__CLEAN=$(printf "%s" "$__DUID" | tr 'A-F' 'a-f' | tr -cd '0-9a-f')
	__LEN=${#__CLEAN}
	[ "$__LEN" -ge 8 ] || return 1

	__TYPE=${__CLEAN:0:4}
	case "$__TYPE" in
		0001)
			__OFFSET=16
			;;
		0003)
			__OFFSET=8
			;;
		*)
			return 1
			;;
	esac

	[ "$__LEN" -gt "$__OFFSET" ] || return 1
	__MACHEX=${__CLEAN:$__OFFSET}
	[ -n "$__MACHEX" ] || return 1

	__HWTYPE=${__CLEAN:4:4}
	case "$__HWTYPE" in
		0001|0006|000f|0010)
			__MACHEX=$(printf "%s\n" "$__MACHEX" | sed -n 's/^\(.\{12\}\).*/\1/p')
			[ -n "$__MACHEX" ] || return 1
			;;
		*)
			return 1
			;;
	esac

	printf "%s\n" "$__MACHEX" | sed 's/../&:/g; s/:$//'
	return 0
}

load_neighbor_hostnames() {
	local __FILE __EXP __MAC __IP __HOST __CLIENT

	__FILE="/tmp/dhcp.leases"
	if [ -f "$__FILE" ]; then
		while read -r __EXP __MAC __IP __HOST __CLIENT; do
			[ -n "$__MAC" ] || continue
			[ -n "$__HOST" ] || continue
			[ "$__HOST" = "*" ] && continue
			record_hostname_for_mac "$__MAC" "$__HOST"
		done < "$__FILE"
	fi

	if [ -n "$UBUS" ]; then
		local __JSON __DEVICES __DEV __IDX __HOST __DUID __HEXMAC __MAC
		__JSON=$($UBUS call dhcp ipv6leases 2>/dev/null)
		if [ -n "$__JSON" ]; then
			if json_load "$__JSON" 2>/dev/null; then
				if json_select "device" >/dev/null 2>&1; then
					json_get_keys __DEVICES
					for __DEV in $__DEVICES; do
						json_select "$__DEV" >/dev/null 2>&1 || continue
						if json_select "leases" >/dev/null 2>&1; then
							__IDX=1
							while json_select "$__IDX" >/dev/null 2>&1; do
								json_get_var __HOST "hostname"
								json_get_var __DUID "duid"
								json_select ".." >/dev/null 2>&1
								[ -n "$__DUID" ] || { __IDX=$((__IDX + 1)); continue; }
								if __MAC=$(duid_to_mac "$__DUID"); then
									record_hostname_for_mac "$__MAC" "$__HOST"
								fi
								__IDX=$((__IDX + 1))
							done
							json_select ".." >/dev/null 2>&1
						fi
						json_select ".." >/dev/null 2>&1
					done
					json_select ".." >/dev/null 2>&1
				fi
				json_cleanup
			fi
		fi
	fi
}

list_device_neighbors() {
	local __DEVICE="$1"
	local __NETWORK="$2"
	local __TMP __LINE __ADDR __MAC __STATE __TOK key value seen macs=""
	local __PREFIX __PREFIX_LEN __PREFIXES=""

	[ -n "$__DEVICE" ] || return 1

	command -v ip >/dev/null 2>&1 || return 1
	command -v mktemp >/dev/null 2>&1 || return 1
	. /usr/share/libubox/jshn.sh

	# Get IPv6 prefixes from the network/interface
	if [ -n "$__NETWORK" ]; then
		# Get prefixes delegated to this network
		local __IFACE_JSON __PREFIX_ITEM
		__IFACE_JSON=$($UBUS call network.interface."$__NETWORK" status 2>/dev/null)
		if [ -n "$__IFACE_JSON" ]; then
			if json_load "$__IFACE_JSON" 2>/dev/null; then
				# Check ipv6-prefix-assignment (downstream prefixes)
				if json_select "ipv6-prefix-assignment" >/dev/null 2>&1; then
					local __IDX=1
					while json_select "$__IDX" >/dev/null 2>&1; do
						json_get_var __PREFIX "address"
						json_get_var __PREFIX_LEN "mask"
						if [ -n "$__PREFIX" ] && [ -n "$__PREFIX_LEN" ]; then
							[ -n "$__PREFIXES" ] && __PREFIXES="$__PREFIXES "
							__PREFIXES="${__PREFIXES}${__PREFIX}/${__PREFIX_LEN}"
						fi
						json_select ".." >/dev/null 2>&1
						__IDX=$((__IDX + 1))
					done
					json_select ".." >/dev/null 2>&1
				fi
				# Also check ipv6-prefix (upstream PD)
				if json_select "ipv6-prefix" >/dev/null 2>&1; then
					local __IDX=1
					while json_select "$__IDX" >/dev/null 2>&1; do
						json_get_var __PREFIX "address"
						json_get_var __PREFIX_LEN "mask"
						if [ -n "$__PREFIX" ] && [ -n "$__PREFIX_LEN" ]; then
							[ -n "$__PREFIXES" ] && __PREFIXES="$__PREFIXES "
							__PREFIXES="${__PREFIXES}${__PREFIX}/${__PREFIX_LEN}"
						fi
						json_select ".." >/dev/null 2>&1
						__IDX=$((__IDX + 1))
					done
					json_select ".." >/dev/null 2>&1
				fi
				json_cleanup
			fi
		fi
	fi

	# Fallback: get prefixes from interface addresses
	if [ -z "$__PREFIXES" ] && [ -n "$__DEVICE" ]; then
		local __ADDR_LINE
		ip -6 addr show dev "$__DEVICE" scope global 2>/dev/null | while read -r __ADDR_LINE; do
			case "$__ADDR_LINE" in
				*inet6*)
					__PREFIX=$(echo "$__ADDR_LINE" | awk '{print $2}' | cut -d'/' -f1)
					__PREFIX_LEN=$(echo "$__ADDR_LINE" | awk '{print $2}' | cut -d'/' -f2)
					if [ -n "$__PREFIX" ] && [ -n "$__PREFIX_LEN" ]; then
						# Extract network prefix (first 64 bits typically)
						__PREFIX=$(echo "$__PREFIX" | cut -d':' -f1-4)
						echo "${__PREFIX}::/${__PREFIX_LEN:-64}"
					fi
					;;
			esac
		done | sort -u | tr '\n' ' ' | read __PREFIXES 2>/dev/null || true
	fi

	load_neighbor_hostnames

	__TMP=$(mktemp 2>/dev/null) || return 1
	ip -6 neigh show dev "$__DEVICE" 2>/dev/null > "$__TMP"

	while read -r __ADDR __LINE; do
		[ -n "$__ADDR" ] || continue
		__ADDR=${__ADDR%%%%*}
		case "$__ADDR" in
			fe80:*)
				continue
				;;
			*)
				;;
		esac

		__MAC=""
		__STATE=""
		set -- $__LINE
		while [ $# -gt 0 ]; do
			case "$1" in
				lladdr)
					shift
					[ $# -gt 0 ] && __MAC=$1
					;;
				FAILED|INCOMPLETE)
					__STATE=$1
					;;
				*)
					;;
			esac
			shift
		done

		[ -n "$__MAC" ] || continue
		[ "$__STATE" = "FAILED" -o "$__STATE" = "INCOMPLETE" ] && continue

		__MAC=$(printf "%s" "$__MAC" | tr 'A-Z' 'a-z')
		key=${__MAC//:/_}
		eval value="\${neighbors_$key}"
		seen=0
		for __TOK in $value; do
			[ "$__TOK" = "$__ADDR" ] && { seen=1; break; }
		done
		[ $seen -eq 1 ] || {
			if [ -n "$value" ]; then
				eval neighbors_$key="\"$value $__ADDR\""
			else
				eval neighbors_$key="\"$__ADDR\""
			fi
		}
		case " $macs " in
			*" $__MAC "*) ;;
			*) macs="$macs $__MAC" ;;
		esac
	done < "$__TMP"

	rm -f "$__TMP"

	json_init
	# Add prefixes array
	json_add_array "prefixes"
	for __PREFIX in $__PREFIXES; do
		[ -n "$__PREFIX" ] && json_add_string "" "$__PREFIX"
	done
	json_close_array
	json_add_array "devices"
	for __MAC in $macs; do
		[ -n "$__MAC" ] || continue
		key=${__MAC//:/_}
		eval value="\${neighbors_$key}"
		eval __HOST="\${neighbor_name_$key}"
		json_add_object ""
		json_add_string "mac" "$__MAC"
		[ -n "$__HOST" ] && json_add_string "hostname" "$__HOST"
		json_add_array "addresses"
		for __TOK in $value; do
			json_add_string "" "$__TOK"
		done
		json_close_array
		json_close_object
	done
	json_close_array
	json_dump
	return 0
}

# preset some variables, wrong or not set in ddns-functions.sh
SECTION_ID="lucihelper"
LOGFILE="$ddns_logdir/$SECTION_ID.log"
DATFILE="$ddns_rundir/$SECTION_ID.$$.dat"	# save stdout data of WGet and other extern programs called
ERRFILE="$ddns_rundir/$SECTION_ID.$$.err"	# save stderr output of WGet and other extern programs called
DDNSPRG="/usr/lib/ddns/dynamic_dns_updater.sh"
VERBOSE=0		# no console logging
# global variables normally set by reading DDNS UCI configuration
use_syslog=0		# no syslog
use_logfile=0		# no logfile

use_ipv6=0		# Use IPv6 - default IPv4
force_ipversion=0	# Force IP Version - default 0 - No
force_dnstcp=0		# Force TCP on DNS - default 0 - No
is_glue=0		# Is glue record - default 0 - No
use_https=0		# not needed but must be set
__explicit_ipv6_source=""	# Track if explicit IPv6 source was set

while getopts ":6d:fghi:l:n:p:s:M:T:S:tu:Lv:VPDAEx:" OPT; do
	case "$OPT" in
		6)	use_ipv6=1;;
		d)	dns_server="$OPTARG";;
		f)	force_ipversion=1;;
		g)	is_glue=1;;
		i)	ip_interface="$OPTARG"; ip_source="interface";;
		l)	lookup_host="$OPTARG";;
		n)	ip_network="$OPTARG";;
		p)	proxy="$OPTARG";;
		s)	ip_script="$OPTARG"; ip_source="script";;
		M)	ip_device="$OPTARG"; [ "$use_ipv6" -eq 0 ] && use_ipv6=1;;
		T)	ip_device_type="$OPTARG";;
		P)	ip_source="prefix"; __explicit_ipv6_source=1; [ "$use_ipv6" -eq 0 ] && use_ipv6=1;;
		D)	ip_source="dhcpv6"; __explicit_ipv6_source=1; [ "$use_ipv6" -eq 0 ] && use_ipv6=1;;
		A)	ip_source="slaac"; __explicit_ipv6_source=1; [ "$use_ipv6" -eq 0 ] && use_ipv6=1;;
		E)	ip_source="eui64"; __explicit_ipv6_source=1; [ "$use_ipv6" -eq 0 ] && use_ipv6=1;;
		x)	ip_prefix_suffix="$OPTARG";;
		t)	force_dnstcp=1;;
		u)	ip_url="$OPTARG"; ip_source="web";;
		h)	usage; exit 255;;
		L)	use_logfile=1;;
		v)	VERBOSE=$OPTARG;;
		S)	SECTION=$OPTARG;;
		V)	printf %s\\n "ddns-scripts $VERSION"; exit 255;;
		:)	usage_err "option -$OPTARG missing argument";;
		\?)	usage_err "invalid option -$OPTARG";;
		*)	usage_err "unhandled option -$OPT $OPTARG";;
	esac
done
shift $((OPTIND - 1 ))	# OPTIND is 1 based

[ "$1" = "--" ] && shift

# Determine ip_source if not explicitly set
if [ -z "$ip_source" ]; then
	if [ -n "$ip_device" ]; then
		# ip_device set without explicit source -> use "device"
		ip_source="device"
	elif [ -n "$ip_network" ]; then
		# ip_network set without explicit source -> use "network"
		ip_source="network"
	fi
fi

[ $# -eq 0 ] && usage_err "missing command"

__RET=0
case "$1" in
	get_registered_ip)
		[ -z "$lookup_host" ] && usage_err "command 'get_registered_ip': 'lookup_host' not set" 
		write_log 7 "-----> get_registered_ip IP"
		[ -z "$SECTION" ] || IPFILE="$ddns_rundir/$SECTION.ip"
		IP=""
		get_registered_ip IP
		__RET=$?
		[ $__RET -ne 0 ] && IP=""
		printf "%s" "$IP"
		;;
	verify_dns)
		[ -z "$dns_server" ] && usage_err "command 'verify_dns': 'dns_server' not set" 
		write_log 7 "-----> verify_dns '$dns_server'"
		verify_dns "$dns_server"
		__RET=$?
		;;
	verify_proxy)
		[ -z "$proxy" ] && usage_err "command 'verify_proxy': 'proxy' not set" 
		write_log 7 "-----> verify_proxy '$proxy'"
		verify_proxy "$proxy"
		__RET=$?
		;;
	get_local_ip)
		[ -z "$ip_source" ] && usage_err "command 'get_local_ip': 'ip_source' not set" 
		[ -n "$proxy" -a "$ip_source" = "web" ] && {
			# proxy defined, used for ip_source=web
			export HTTP_PROXY="http://$proxy"
			export HTTPS_PROXY="http://$proxy"
			export http_proxy="http://$proxy"
			export https_proxy="http://$proxy"
		}
		IP=""
		if [ "$ip_source" = "web" -o  "$ip_source" = "script" ]; then
			# we wait only 3 seconds for an
			# answer from "web" or "script"
			write_log 7 "-----> timeout 3 -- get_current_ip IP"
			timeout 3 -- get_current_ip IP
		else
			write_log 7 "-----> get_current_ip IP"
			get_current_ip IP
		fi
		__RET=$?
		[ $__RET -ne 0 ] && IP=""
		printf "%s" "$IP"
		;;
	start)
		[ -z "$SECTION" ] &&  usage_err "command 'start': 'SECTION' not set"
		if [ "$VERBOSE" -eq 0 ]; then	# start in background
			"$DDNSPRG" -v 0 -S "$SECTION" -- start &
		else
			"$DDNSPRG" -v "$VERBOSE" -S "$SECTION" -- start
		fi
		;;
	reload)
		"$DDNSPRG" -- reload
		;;
	restart)
		"$DDNSPRG" -- stop
		sleep 1
		"$DDNSPRG" -- start
		;;
	stop)
		if [ -n "$SECTION" ]; then
			# section stop
			"$DDNSPRG" -S "$SECTION" -- stop
		else
			# global stop
			"$DDNSPRG" -- stop
		fi
		;;
	list_neighbors)
		if [ -z "$ip_interface" ] && [ -n "$ip_network" ]; then
			network_get_device ip_interface "$ip_network" || usage_err "command 'list_neighbors': unable to resolve network '$ip_network'"
		fi
		[ -n "$ip_interface" ] || usage_err "command 'list_neighbors': 'ip_interface' or 'ip_network' required"
		list_device_neighbors "$ip_interface" "$ip_network"
		__RET=$?
		;;
	*)
		__RET=255
		;;
esac

# remove out and err file
[ -f "$DATFILE" ] && rm -f "$DATFILE"
[ -f "$ERRFILE" ] && rm -f "$ERRFILE"
exit $__RET

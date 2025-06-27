#!/usr/bin/env sh
# Simplified cfdisk replacement that prints partition information.

show_help() {
    cat <<'USAGE'
Usage: cfdisk.sh [OPTIONS] [DEVICE]
Display partition information for DEVICE (default /dev/vda).
Options:
  -P [t|r]   Print the partition table in a simple text format (t) or raw (r)
  -h, --help Show this help message
  -v         Print version information
USAGE
}

VERSION="cfdisk.sh 0.1"

opt_P=""
device="/dev/vda"

while [ $# -gt 0 ]; do
    case "$1" in
        -P)
            shift
            [ $# -gt 0 ] || { echo "cfdisk: option requires an argument -- P" >&2; exit 1; }
            opt_P="$1"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "$VERSION"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "cfdisk: unknown option $1" >&2
            exit 1
            ;;
        *)
            device="$1"
            ;;
    esac
    shift
done

device=${device#/dev/}
sys="/sys/block/$device"
if [ ! -d "$sys" ]; then
    echo "cfdisk: device /dev/$device not found" >&2
    exit 1
fi

sector_size=$(cat "$sys/queue/hw_sector_size")
disk_sectors=$(cat "$sys/size")
disk_mb=$((disk_sectors * sector_size / 1024 / 1024))

print_table() {
    printf "%-12s %-10s\n" "Device" "Size(MB)"
    for part in "$sys"/${device}[0-9]*; do
        [ -e "$part" ] || continue
        name="$(basename "$part")"
        size=$(cat "$part/size")
        mb=$((size * sector_size / 1024 / 1024))
        printf "/dev/%-8s %10d\n" "$name" "$mb"
    done
}

print_raw() {
    echo "Disk /dev/$device: $disk_mb MB"
    for part in "$sys"/${device}[0-9]*; do
        [ -e "$part" ] || continue
        name="$(basename "$part")"
        size=$(cat "$part/size")
        echo "$name $size"
    done
}

case "$opt_P" in
    t)
        print_table
        ;;
    r)
        print_raw
        ;;
    "")
        echo "Disk /dev/$device: $disk_mb MB"
        print_table
        ;;
    *)
        echo "cfdisk: invalid -P option" >&2
        exit 1
        ;;
esac


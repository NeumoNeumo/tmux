#!/usr/bin/env bash

# UPLOAD and DOWNLOAD index
readonly UPLOAD=0
readonly DOWNLOAD=1

# SIZE index are the multiple of the unit byte and value the internationally recommended unit symbol in sec
readonly SIZE=(
  [1]='B/s'
  [1000]='kB/s'
  [1000000]='MB/s'
  [1000000000]='GB/s'
)

# interface_get try to automaticaly get the used interface if network_name is empty
interface_get() {
  name="$(tmux show-option -gqv "@dracula-network-bandwidth")"

  if [[ -z $name ]]; then
    case "$(uname -s)" in
    Linux)
      if type ip >/dev/null; then
        name="$(ip -o route show default | awk '{print $5; exit}')"
      fi
      ;;
    Darwin)
      if type route >/dev/null; then
        name="$(route -n get 192.168.0.0 2>/dev/null | awk '/interface: / {print $2}')"
      fi
      ;;
    esac
  fi

  echo "$name"
}

# interface_bytes give an interface name and return both tx/rx Bytes, separated by whitespace (upload first)
interface_bytes() {
  case "$(uname -s)" in
  Linux)
    upload_rate=$(cat "/sys/class/net/$1/statistics/tx_bytes")
    download_rate=$(cat "/sys/class/net/$1/statistics/rx_bytes")

    echo "$upload_rate $download_rate"
    ;;
  Darwin)
    # column 7 is Ibytes (in bytes, rx, download) and column 10 is Obytes (out bytes, tx, upload)
    netstat -nbI "$1" | tail -n1 | awk '{print $10 " " $7}'
    ;;
  esac
}

# get_bandwidth return the number of bytes exchanged for tx and rx
get_bandwidth() {
  local interface="$1"
  local interval="$2"

  IFS=' ' read -r old_upload old_download <<< "$(interface_bytes "$interface")"
  sleep "$interval"
  IFS=' ' read -r new_upload new_download <<< "$(interface_bytes "$interface")"
  upload_rate=$(( (new_upload - old_upload) / interval ))
  download_rate=$(( (new_download - old_download) / interval ))

  # set to 0 by default
  echo "${upload_rate:-0} ${download_rate:-0}"
}

bandwidth_to_unit() {
  local size=1
  for i in "${!SIZE[@]}"; do
    if (($1 < i)); then
      break
    fi
    size="$i"
  done

  local result
  # Use awk to format the value to 3 significant figures
  result=$(awk -v bytes="$1" -v divisor="$size" '
    BEGIN {
      if (bytes == 0) {
        printf "0.00";
        exit;
      }
      val = bytes / divisor;
      if (val < 10) {
        fmt = "%.2f";
      } else if (val < 100) {
        fmt = "%.1f";
      } else {
        fmt = "%.0f";
      }
      printf(fmt, val);
    }' </dev/null)

  echo "$result ${SIZE[$size]}"
}

main() {
  counter=0
  bandwidth=()

  network_name=""
  show_interface="$(tmux show-option -gqv "@dracula-network-bandwidth-show-interface")"
  interval="$(tmux show-option -gqv "@dracula-network-bandwidth-interval")"

  if [[ -z $interval_update ]]; then
    interval_update=0
  fi

  printf "%4s%4s↓ %4s%4s↑\n" - B/s - B/s

  while true; do
    if ((counter == 0)); then
      counter=60
      network_name="$(interface_get)"
    fi

    IFS=" " read -ra bandwidth <<<"$(get_bandwidth "$network_name" "$interval")"

    if [[ $show_interface == "true" ]]; then echo -n "[$network_name] "; fi
    printf "%4s%4s↓ %4s%4s↑\n" $(bandwidth_to_unit "${bandwidth[$DOWNLOAD]}") $(bandwidth_to_unit "${bandwidth[$UPLOAD]}")

    ((counter = counter - 1))
  done
}

#run main driver
main

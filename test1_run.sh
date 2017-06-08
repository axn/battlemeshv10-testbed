#!/bin/sh
. scripts/functions_wbm.sh

FILE="${1:-./test1_ip_pairs.txt}"
DURATION_OVERALL="${2:-900}"		# [seconds]
DURATION_TEST="${3:-10}"		# [seconds]
#
FILE_REPORT="/tmp/myreport.$$"		# internally used only
GOOD=0
BAD=0
BYTES_TRANSFERED=0

# here we are measuring data-transmission between 2 nodes
# we iterate over a list of ~100 pairs.
# we abort after e.g. 900 seconds
# we measure one protocol after another
# we measure with and without airtime fairness

echo "# test1: $(date) DURATION_OVERALL: $DURATION_OVERALL DURATION_TEST: $DURATION_TEST"
log "using file '$FILE', DURATION_OVERALL: $DURATION_OVERALL DURATION_TEST: $DURATION_TEST"

parse_report()
{
	local file="$1"
	local word word_old

	# output e.g.:
	# [...]
	# [  5]  0.0-10.0 sec  5357600 Bytes  4279482 bits/sec
	# [  4]  0.0-10.6 sec  393216 Bytes  297583 bits/sec
	for word in $( tail -n2 "$file" | grep 'bits/sec' ); do
		case "$word" in
			'Bytes')
				if isnumber "$word_old"; then
					BYTES_TRANSFERED=$(( BYTES_TRANSFERED + word_old ))
					log "bytes: $word_old"
					echo "# ip1: $IP1 ip2: $IP2 bytes: $word_old"
				else
					echo "# ip1: $IP1 ip2: $IP2 bytes: 0"
					log "bad bytes: '$word_old'"
				fi

				word_old=
			;;
			*)
				word_old="$word"
			;;
		esac
	done

	[ -n "$word" ] || echo "# ip1: $IP1 ip2: $IP2 bytes: -1"
}

TIME_END=$(( $( uptime_in_seconds ) + DURATION_OVERALL ))

for PROTOCOL in babel batman-adv bmx7 olsr1 olsr2; do
	./launch_new_protocol.sh '' $PROTOCOL
for AIRTIME_FAIRNESS in on off; do
while read -r LINE
do
	[ $( uptime_in_seconds ) -gt $TIME_END ] && break

	set -- $LINE
	IP1="$1"
	IP2="$2"
	if [ "$IP1" = "$IP2" ]; then
		# such a test does not make sense
		continue
	else
		log "IP1/server: $IP1 IP2/client: $IP2"

		# is needed, because 80211s is reactive
		ping_ok "$IP1" || {
			echo "# ip1: $IP1 ip2: $IP2 bytes: -2"
			log "IP1/server: unreachable, skipping"
			continue
		}

		ping_ok "$IP2" || {
			echo "# ip1: $IP1 ip2: $IP2 bytes: -3"
			log "IP2/client: unreachable, skipping"
			continue
		}
	fi

	execute_command_via_ssh "$IP1" "for F in /sys/kernel/debug/ieee80211/phy*/*/airtime_flags; do echo $AIRTIME_FAIRNESS >$F"
	execute_command_via_ssh "$IP2" "for F in /sys/kernel/debug/ieee80211/phy*/*/airtime_flags; do echo $AIRTIME_FAIRNESS >$F"
	execute_command_via_ssh "$IP1" "killall iperf; cat /tmp/MESHPROTO || echo 'unknown" >"$FILE_REPORT.proto1"
	execute_command_via_ssh "$IP1" "iperf --server --daemon --print_mss"
	execute_command_via_ssh "$IP2" "killall iperf; cat /tmp/MESHPROTO || echo 'unknown" >"$FILE_REPORT.proto2"
	execute_command_via_ssh "$IP2" "iperf --time $DURATION_TEST --client $( convert_management2test_ip "$IP1" ) --format bytes --dualtest --listenport 9001" >"$FILE_REPORT"
	execute_command_via_ssh "$IP1" "killall iperf"

	PROTO1=; read -r PROTO1 <"$FILE_REPORT.proto1"
	PROTO2=; read -r PROTO2 <"$FILE_REPORT.proto2"
	echo "# protocol: $PROTOCOL airtime_fairness: $AIRTIME_FAIRNESS"
	[ "$PROTO1" != "$PROTO2" -o "$PROTO1" != "$PROTOCOL" ] && echo "# error: PROTO/1/2: $PROTOCOL/$PROTO1/$PROTO2"

	parse_report "$FILE_REPORT"
	rm -f "$FILE_REPORT"
done <"$FILE"
done
done

echo "# test1: $(date) - ready"
log "summary: good: $GOOD bad: $BAD BYTES_TRANSFERED: $BYTES_TRANSFERED"

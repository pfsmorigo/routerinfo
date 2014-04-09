#!/bin/bash

STAT_FREQ=1

BASE_DIR="$(cd $(dirname $0); pwd)"

COOKIE_FILE="$BASE_DIR/cookies.txt"
TEMP_FILE="/tmp/routerinfo_temp"

GENERAL="--no-check-certificate --keep-session-cookies"
SILENCE="--quiet"
VERBOSE="--verbose --debug"

SAVE_COOKIES="--save-cookies $COOKIE_FILE"
LOAD_COOKIES="--load-cookies $COOKIE_FILE"

ROUTER_IP=$(ip r list | grep default | cut -d " " -f 3)
URL=http://$ROUTER_IP/html/status/overview.asp

UPRATE_MAX=0
DOWNRATE_MAX=0
LAST_REC=0

format_number() {
	BASE=
	SUFFIX=
	SCALE=1

	case $2 in
		speed) SUFFIX="b/s";;
		size)  SUFFIX="B";;
		*)     SUFFIX="(???)";;
	esac

	if [ -n "$3" ]; then
		BASE=$3
	else
		if   [ $(( $1/(1024*1024*1024) )) != 0 ]; then
			BASE=G
		elif [ $(( $1/(1024*1024) )) != 0 ]; then
			BASE=M
		elif [ $(( $1/1024 )) != 0 ]; then
			BASE=K
		fi
	fi

	[ -n "$4" ] && SCALE=$4

	case $BASE in
		G) echo -n "$(bc <<< "scale=$SCALE;$1/(1024*1024*1024)")G${SUFFIX}";;
		M) echo -n "$(bc <<< "scale=$SCALE;$1/(1024*1024)")M${SUFFIX}";;
		K) echo -n "$(bc <<< "scale=$SCALE;$1/(1024)")K${SUFFIX}";;
		*) echo -n "$1${SUFFIX}";;
	esac
}

while true; do
	wget $GENERAL $SILENCE $LOAD_COOKIES $URL -O $TEMP_FILE

	STATISTICS=$(cat $TEMP_FILE | grep WanStatistics | tr -d "'")
	IPDNS=$(cat $TEMP_FILE | grep wanIPDNS | tr -d "'")

	#echo "========"
	#echo $STATISTICS
	#echo "========"
	#echo $IPDNS
	#echo "========"

	IP_V4=$(echo $IPDNS | awk '{ print $4 }')
	UPRATE=$(echo $STATISTICS | awk '{ print $5 }')
	DOWNRATE=$(echo $STATISTICS | awk '{ print $9 }')
	UPVOLUME=$(echo $STATISTICS | awk '{ print $13 }')
	DOWNVOLUME=$(echo $STATISTICS | awk '{ print $17 }')

	if [ -z "$DOWNVOLUME" ] || [[ "$DOWNVOLUME" =~ '^[0-9]+$' ]]; then
		echo "(no info)"
	else
		SUMVOLUME=$(( $UPVOLUME + $DOWNVOLUME ))

		if [ "$1" == "table" ]; then
			printf "%15s   ▲ %10s   ▼ %10s   %7s\n" $IP_V4 \
				$(format_number $UPRATE speed K) $(format_number $DOWNRATE speed K) \
				$(format_number $SUMVOLUME size G)
		else
			printf "%s ▲ %s ▼ %s (%s)\n" $IP_V4 \
				$(format_number $UPRATE speed) $(format_number $DOWNRATE speed) \
				$(format_number $SUMVOLUME size)
		fi

		[ $UPRATE -gt $UPRATE_MAX ] && UPRATE_MAX=$UPRATE
		[ $DOWNRATE -gt $DOWNRATE_MAX ] && DOWNRATE_MAX=$DOWNRATE

		NOW=$(date +%s)
		if [ $(( $NOW - $LAST_REC )) -gt $STAT_FREQ ]; then
			printf "%s %s,%s,%s,%s,%s,%s\n" \
				$(date +"%F %T") $IP_V4 \
				$UPVOLUME $DOWNVOLUME $UPRATE_MAX $DOWNRATE_MAX >> /var/local/routerinfo.csv

			UPRATE_MAX=0
			DOWNRATE_MAX=0
			LAST_REC=$NOW
		fi
	fi

	[ "$1" = "once" ] && exit
	sleep 2
done


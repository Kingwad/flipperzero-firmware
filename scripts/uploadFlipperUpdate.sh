#!/bin/bash

firmwaredir=$(dirname $0)/..
progresslog=${HOME}/flipperUpdate.log

log () {
	echo "$1" 1>&2
	echo "$1" >> ${progresslog}
}

initserial() {
	serialoutput=$(mktemp)
	device=$(find /dev -regex /dev/ttyACM.*)
	if [[ $(echo "${device}"|wc -l) -ne 1 ]]; then
		log "Could not find device"
		exit 1
	fi
	stty -F ${device} 115200 line 0 min 1 time 5 ignbrk -brkint -icrnl -imaxbel -opost -onlcr -isig -icanon -iexten -echo -echoe -echok -echoctl -echoke
	cat ${device} > ${serialoutput} &
	sleep 1
}

cleanupserial () {
	local jobsrunning=$(jobs|grep "cat \${device} > \${serialoutput} &")
	if [[ ! -z "$(jobs)" ]]; then
		kill %1
	fi
	if [[ ! -z ${serialoutput} ]]; then
		echo "Serial Output" >> ${progresslog}
		cat ${serialoutput} >> ${progresslog}
		rm ${serialoutput}
	fi
	exit
}

checkserial () {
	if [ -z "$1" ]; then
		log "checkserial missing expectation"
		cleanupserial
	fi
	local expectation="$1"
	local result=$(tail -n1 ${serialoutput})
	[[ "${result}" = "${expectation}" ]]
	return $?
}

uploadchunk() {
	if [ -z "$1" ]; then
		log "uploadchunk missing source filename"
		cleanupserial
	fi
	if [ -z "$2" ]; then
		log "uploadchunk missing destination filename"
		cleanupserial
	fi
	if [ -z "$3" ]; then
		log "uploadchunk missing start position"
		cleanupserial
	fi
	if [ -z "$4" ]; then
		log "uploadchunk missing byte count"
		cleanupserial
	fi
	if [ $4 -gt 65535 ]; then
		log "uploadchunk byte count $3 too high"
		cleanupserial
	fi
	local source=$1
	local destination=$2
	local start=$3
	local size=$4
	log "preparing to upload $(basename ${source}) start ${start} size ${size}"
	echo -ne "storage write_chunk ${destination} ${size}\r" > ${device}
	checkserial "Ready"
	if [ $? ]; then
		log "uploading"
		dd if=${source} of=${device} bs=1 count=${size} skip=${start}
		if [ $? ]; then
			log "success"
		else
			log "faulure"
			cleanupserial
		fi
	else
		log "not ready for transfer"
		cleanupserial
	fi
}

uploadfile () {
	if [ -z "$1" ]; then
		log "uploadfile received no file path"
		cleanupserial
	fi
	if [ -z "$2" ]; then
		log "uploadfile received no destication dir"
		cleanupserial
	fi
	local source=$1
	local size=$(stat -c%s ${source})
	local destination="$2/$(basename ${source})"
	local bytessent=0
	local maxsend=65535
	if [ -z ${size} ]; then
		log "uploadfile could not get size of ${source}"
		cleanupserial
	fi
	while [ "${bytessent}" -lt "${size}" ]; do
		local bytestosend=$(echo "${size} - ${bytessent}"|bc)
		if [ "${bytestosend}" -gt "${maxsend}" ]; then
			bytestosend=${maxsend}
		fi
		uploadchunk "${source}" "${destination}" ${bytessent} ${bytestosend}
		bytessent=$(echo "${bytessent} + ${bytestosend}"|bc)
	done
}

initserial
echo "$(date)" >> ${progresslog}
if [ ! -d ${firmwaredir} ]; then
	log "Firmware directory does not exist"
	exit 1
fi
cd ${firmwaredir}

gitcommit=$(git rev-parse --short HEAD || echo -n "unknown")
log "git commit ${gitcommit}"
dirty=$(git diff --quiet; echo $?)
updatedir=dist/f7/f7-update-local-${gitcommit}
if [ 1 -eq ${dirty} ]; then
	updatedir=${updatedir}-dirty
fi
log "Update directory is ${updatedir}"

if [ ! -d ${updatedir} ]; then
	log "Update directory does not exist"
	exit 1
fi

flipperupdatedir=/ext/update/$(basename ${updatedir})
echo -ne "storage mkdir ${flipperupdatedir}\r" > ${device}
if [ 0 -ne $? ]; then
	log "error writing to flipper"
	exit 1
fi
sleep 1

for file in ${updatedir}/*; do
	uploadfile "${file}" "${flipperupdatedir}"
done
cleanupserial

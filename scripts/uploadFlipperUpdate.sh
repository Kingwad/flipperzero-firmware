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
	if [[ ( -z "${device}" ) || ( $(echo "${device}"|wc -l) -ne 1 ) ]]; then
		log "could not find device"
		exit 1
	fi
	stty -F ${device} 115200 line 0 min 1 time 5 ignbrk -brkint -icrnl -imaxbel -opost -onlcr -isig -icanon -iexten -echo -echoe -echok -echoctl -echoke
	cat ${device} > ${serialoutput} &
	sleep 1
}

cleanupserial () {
	local jobsrunning=$(jobs|grep "cat \${device} > \${serialoutput} &")
	if [[ -n "$(jobs)" ]]; then
		kill %1
	fi
	if [[ -n "${serialoutput}" ]]; then
		echo "Serial Output" >> ${progresslog}
		cat ${serialoutput} >> ${progresslog}
		rm ${serialoutput}
	fi
	exit 0
}

checkserial () {
	if [[ -z "$1" ]]; then
		log "checkserial missing expectation"
		cleanupserial
	fi
	local expectation="$1"
	local result=$(tail -n1 ${serialoutput})
	[[ "${result}" == "${expectation}" ]]
}

waitforprompt() {
	local timeout=10
	local loop=0
	local prompt=">: "
	if [[ -n "$1" ]]; then
		prompt="$1"
	fi
	while [[ ${loop} -eq 0 ]]; do
		sleep 1
		timeout=$(echo "${timeout} - 1"|bc)
		if [[ $timeout -lt 1 ]]; then
			loop=2
		fi
		checkserial "${prompt}"
		if [[ $? -eq 0 ]]; then
			loop=1
		fi
	done
	[[ ${loop} = 1 ]]
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
	checkserial ">: "
	if [[ $? -eq 0 ]]; then
		echo -ne "storage write_chunk ${destination} ${size}\r" > ${device}
	else
		log "not ready for upload"
		cleanupserial
	fi
	waitforprompt $'Ready\r'
	if [[ $? -eq 0 ]]; then
		log "uploading"
		dd if=${source} of=${device} bs=1 count=${size} skip=${start}
		if [[ $? -eq 0 ]]; then
			log "success"
		else
			log "faulure"
			cleanupserial
		fi
	else
		log "not ready for transfer"
		cleanupserial
	fi
	waitforprompt
	if [[ $? -ne 0 ]]; then
		log "no prompt after file transfer"
		cleanupserial
	fi
}

uploadfile () {
	if [[ -z "$1" ]]; then
		log "uploadfile received no file path"
		cleanupserial
	fi
	if [[ -z "$2" ]]; then
		log "uploadfile received no destication dir"
		cleanupserial
	fi
	local source=$1
	local size=$(stat -c%s ${source})
	local destination="$2/$(basename ${source})"
	local bytessent=0
	local maxsend=65535
	if [[ -z "${size}" ]]; then
		log "uploadfile could not get size of ${source}"
		cleanupserial
	fi
	while [[ ${bytessent} -lt ${size} ]]; do
		local bytestosend=$(echo "${size} - ${bytessent}"|bc)
		if [[ ${bytestosend} -gt ${maxsend} ]]; then
			bytestosend=${maxsend}
		fi
		uploadchunk "${source}" "${destination}" ${bytessent} ${bytestosend}
		bytessent=$(echo "${bytessent} + ${bytestosend}"|bc)
	done
	local localmd5=$(md5sum ${source}|cut -d' ' -f1)
	echo -ne "storage md5 ${destination}\r" > ${device}
	waitforprompt
	if [[ $? -ne 0 ]]; then
		log "Failed to get md5"
		cleanupserial
	fi
	local flipmd5=$(tail -n3 ${serialoutput}|head -n1|tr -d "\n\r")
	if [[ "${localmd5}" == "${flipmd5}" ]]; then
		log "md5 match"
	else
		log "md5 mismatch"
		cleanupserial
	fi
}

initserial
echo "$(date)" >> ${progresslog}
if [[ ! -d ${firmwaredir} ]]; then
	log "Firmware directory does not exist"
	exit 1
fi
cd ${firmwaredir}

gitcommit=$(git rev-parse --short HEAD || echo -n "unknown")
log "git commit ${gitcommit}"
dirty=$(git diff --quiet; echo $?)
updatedir=dist/f7/f7-update-local-${gitcommit}
if [[ ${dirty} -eq 1 ]]; then
	updatedir=${updatedir}-dirty
fi
log "Update directory is ${updatedir}"

if [[ ! -d ${updatedir} ]]; then
	log "Update directory does not exist"
	exit 1
fi

flipperupdatedir=/ext/update/$(basename ${updatedir})
waitforprompt
if [[ 0 -ne $? ]]; then
	log "flipper not ready"
	cleanupserial
fi
echo -ne "storage mkdir ${flipperupdatedir}\r" > ${device}
waitforprompt
if [[ 0 -ne $? ]]; then
	log "error creating directory on flipper"
	cleanupserial
fi

for file in ${updatedir}/*; do
	uploadfile "${file}" "${flipperupdatedir}"
done
log "upload to flipper completed successfully"
cleanupserial

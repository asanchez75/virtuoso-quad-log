#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

LOG_FILE_LOCATION=${LOG_FILE_LOCATION:-/usr/local/var/lib/virtuoso/db}

if [ "${1:-}" = "server" ]; then
	/usr/local/bin/virtuoso-t -f -c /usr/local/var/lib/virtuoso/db/virtuoso.ini
else
	if [ -n "${VIRTUOSO_PORT_1111_TCP_ADDR:-}" -a -n "${VIRTUOSO_PORT_1111_TCP_PORT:-}" ]; then
		ISQL_CMD="isql -H ${VIRTUOSO_PORT_1111_TCP_ADDR} -S ${VIRTUOSO_PORT_1111_TCP_PORT} -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"
	else
		ISQL_CMD="isql -H $VIRTUOSO_ISQL_ADDRESS -S $VIRTUOSO_ISQL_PORT -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"
	fi

	set +o errexit
	$ISQL_CMD <<-'EOF' | grep -q 'parse_trx'
		SET CSV=ON;
		SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME = 'DB.DBA.parse_trx';
		exit;
		EOF
	GREPRESULT=${PIPESTATUS[1]}
	set -o errexit
	if [ $GREPRESULT -ne 0 ]; then
		read -p "To read the transaction log from the server I need to install a few stored procedures on the virtuoso server. All starting with 'parse_trx'. Is that okay? [yn]" insert_procedure
		if [ "$insert_procedure" != "y" ]; then
			echo "Without the stored procedure I can't be of much use. Sorry. You might want to run me connected to a dummy virtuoso server in a container as detailed in the README."
			exit 1
		else
			echo "Inserting stored procedure:"
			$ISQL_CMD < parse_trx.sql
			echo "done."
		fi
	fi
	mkdir -p dumpdir
	cd dumpdir
	$ISQL_CMD > output <<-EOF
		checkpoint;
		parse_trx_files('$LOG_FILE_LOCATION');
		exit;
	EOF
	csplit output "/^# start: /" '{*}'
	#loop over all files
	for file in `ls xx*`; do
		if [ `wc -l $file | grep -o '^[0-9]\+'` -gt 1 ]; then # first line is the header, so a one-line file is effectively empty
					 # line with the filename, just the filename,		        remove .trx and trailing spaces, keep only the 14 digits at then end (not y10k proof)
			timestamp=`head -n1 $file        | sed 's|^# start:.*/\(.*\)|\1|' | sed 's/\.trx *$//'             | grep -o '[0-9]\{14\}$' || echo ''`
			if [ -n "$timestamp" ]; then
				mv $file "rdfpatch-${timestamp}"
			else
				rm $file
			fi
		else
			rm $file
		fi
	done
	rm output
fi

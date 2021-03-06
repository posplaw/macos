#!/bin/bash -e
#
# 2011-04-18 modified to use standardize-scutil-output
# Modified by eduVPN to avoid potential filename collisions: tunnelblick -> eduvpn, Tunnelblick -> eduVPN, TUNNELBLICK -> EDUVPN

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# Quick check - is the configuration there?
if ! scutil -w State:/Network/OpenVPN &>/dev/null -t 1 ; then
	# Configuration isn't there, so we forget it
	exit 0
fi

EDUVPN_CONFIG="$( scutil <<-EOF
	open
	show State:/Network/OpenVPN
	quit
EOF
)"

ARG_IGNORE_OPTION_FLAGS="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*IgnoreOptionFlags :' | sed -e 's/^.*: //g')"
ARG_RESTORE_ON_DNS_RESET="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*RestoreOnDNSReset :' | sed -e 's/^.*: //g')"
ARG_RESTORE_ON_WINS_RESET="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*RestoreOnWINSReset :' | sed -e 's/^.*: //g')"
SCRIPT_LOG_FILE="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*ScriptLogFile :' | sed -e 's/^.*: //g')"
PROCESS="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*PID :' | sed -e 's/^.*: //g')"
PSID="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*Service :' | sed -e 's/^.*: //g')"
# Don't need: ARG_MONITOR_NETWORK_CONFIGURATION="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*MonitorNetwork :' | sed -e 's/^.*: //g')"
# Don't need: LEASEWATCHER_PLIST_PATH="$(echo "${EDUVPN_CONFIG}" | grep -i '^[[:space:]]*LeaseWatcherPlistPath :' | sed -e 's/^.*: //g')"

# If we have a process, then we check the DNS and WINS status...
# ..._OLD is the pre-VPN value
# ..._NOW is the current value
# ..._GOOD is the expected (computed) post-VPN value

# Give the new network configuration a chance to settle down
sleep 1

if (( M=${PROCESS:-0} )) ; then

	# What's the correct DNS info?
	DNS_GOOD="$( scutil <<-EOF
		open
		show State:/Network/OpenVPN/DNS
		quit
EOF
)"
    # What's the old DNS info?
    DNS_OLD="$( scutil <<-EOF
        open
        show State:/Network/OpenVPN/OldDNS
        quit
EOF
)"
	# What's the current DNS info?
	DNS_NOW="$( scutil <<-EOF
		open
		show State:/Network/Global/DNS
		quit
EOF
)"

	# What's the correct WINS info?
    WINS_GOOD="$( scutil <<-EOF
		open
		show State:/Network/OpenVPN/SMB
		quit
EOF
)"
    # What's the old WINS info?
    WINS_OLD="$( scutil <<-EOF
        open
        show State:/Network/OpenVPN/OldSMB
        quit
EOF
)"
	# What's the current WINS info?
	WINS_NOW="$( scutil <<-EOF
		open
		show State:/Network/Global/SMB
		quit
EOF
)"
    
    # "Standardize" the output from scutil
    SSO_PATH="$(dirname "${0}")/standardize-scutil-output"
    DNS_GOOD="$(echo "$DNS_GOOD"   | "${SSO_PATH}" ${ARG_IGNORE_OPTION_FLAGS})"
    DNS_OLD="$(echo "$DNS_OLD"     | "${SSO_PATH}" ${ARG_IGNORE_OPTION_FLAGS})"
    DNS_NOW="$(echo "$DNS_NOW"     | "${SSO_PATH}" ${ARG_IGNORE_OPTION_FLAGS})"
    WINS_GOOD="$(echo "$WINS_GOOD" | "${SSO_PATH}" ${ARG_IGNORE_OPTION_FLAGS})"
    WINS_OLD="$(echo "$WINS_OLD"   | "${SSO_PATH}" ${ARG_IGNORE_OPTION_FLAGS})"
    WINS_NOW="$(echo "$WINS_NOW"   | "${SSO_PATH}" ${ARG_IGNORE_OPTION_FLAGS})"
    
    # If the DNS configuration has changed
    # Then if it is the way it was pre-VPN
    #      Then if OK to do so, restore to the post-VPN configuration
    #      Otherwise restart the connection
    # If the WINS configuration has changed
    # Then if it is the way it was pre-VPN
    #      Then if OK to do so, restore to the post-VPN configuration
    #      Otherwise restart the connection
    NOTHING_DISPLAYED="true"
	if [ "${DNS_GOOD}" != "${DNS_NOW}" ] ; then
        NOTHING_DISPLAYED="false"
        echo "$(date '+%a %b %e %T %Y') *eduVPN leasewatch: A network configuration change was detected" >> "${SCRIPT_LOG_FILE}"

        DNS_CHANGES_MSG="			DNS configuration has changed:
			--- BEGIN EXPECTED DNS CFG ---
			${DNS_GOOD}
			---- END EXPECTED DNS CFG ----
            
			--- BEGIN CURRENT DNS CFG ---
			${DNS_NOW}
			---- END CURRENT DNS CFG ----
            
			--- BEGIN PRE-VPN DNS CFG ---
			${DNS_OLD}
			---- END PRE-VPN DNS CFG ----"
        echo "${DNS_CHANGES_MSG}" >> "${SCRIPT_LOG_FILE}"
        if [ "${DNS_NOW}" = "${DNS_OLD}" ] ; then
            # DNS changed, but to the pre-VPN settings
            if ${ARG_RESTORE_ON_DNS_RESET} ; then
                echo "Restoring the expected DNS settings." >> "${SCRIPT_LOG_FILE}"
                scutil <<-EOF
                    open
                    get State:/Network/OpenVPN/DNS
                    set State:/Network/Service/${PSID}/DNS
                    quit
EOF
            else
                echo "Sending USR1 to OpenVPN (process ID ${PROCESS}) to restart the connection." >> "${SCRIPT_LOG_FILE}"
                # sleep 1 so log message is displayed before we start getting log messages from OpenVPN about the restart
                sleep 1
                kill -USR1 ${PROCESS}
                # We're done here, so no need to wait around.
                exit 0
            fi
        else
            # DNS changed, but not to the pre-VPN settings
            echo "Sending USR1 to OpenVPN (process ID ${PROCESS}) to restart the connection." >> "${SCRIPT_LOG_FILE}"
            # sleep 1 so log message is displayed before we start getting log messages from OpenVPN about the restart
            sleep 1
            kill -USR1 ${PROCESS}
            # We're done here, so no need to wait around.
            exit 0
        fi
	fi

	if [ "${WINS_GOOD}" != "${WINS_NOW}" ] ; then
        if ${NOTHING_DISPLAYED} ; then
            NOTHING_DISPLAYED="false"
            echo "$(date '+%a %b %e %T %Y') *eduVPN leasewatch: A network configuration change was detected" >> "${SCRIPT_LOG_FILE}"
        fi
        WINS_CHANGES_MSG="			WINS configuration has changed:
			--- BEGIN EXPECTED WINS CFG ---
			${WINS_GOOD}
			---- END EXPECTED WINS CFG ----
            
			--- BEGIN CURRENT WINS CFG ---
			${WINS_NOW}
			---- END CURRENT WINS CFG ----
            
			--- BEGIN PRE-VPN WINS CFG ---
			${WINS_OLD}
			---- END PRE-VPN WINS CFG ----"
        echo "${WINS_CHANGES_MSG}" >> "${SCRIPT_LOG_FILE}"

        if [ "${WINS_NOW}" = "${WINS_OLD}" ] ; then
            # WINS changed, but to the pre-VPN settings
            if ${ARG_RESTORE_ON_WINS_RESET} ; then
                echo "Restoring the expected WINS settings." >> "${SCRIPT_LOG_FILE}"
                scutil <<-EOF
                    open
                    get State:/Network/OpenVPN/SMB
                    set State:/Network/Service/${PSID}/SMB
                    quit
EOF
            else
                echo "Sending USR1 to OpenVPN (process ID ${PROCESS}) to restart the connection." >> "${SCRIPT_LOG_FILE}"
                # sleep 1 so log message is displayed before we start getting log messages from OpenVPN about the restart
                sleep 1
                kill -USR1 ${PROCESS}
                # We're done here, so no need to wait around.
                exit 0
            fi
        else
            # WINS changed, but not to the pre-VPN settings
            echo "Sending USR1 to OpenVPN (process ID ${PROCESS}) to restart the connection." >> "${SCRIPT_LOG_FILE}"
            # sleep 1 so log message is displayed before we start getting log messages from OpenVPN about the restart
            sleep 1
            kill -USR1 ${PROCESS}
            # We're done here, so no need to wait around.
            exit 0
        fi
	fi
    if ${NOTHING_DISPLAYED} ; then
        echo "$(date '+%a %b %e %T %Y') *eduVPN leasewatch: A system configuration change was ignored because it was not relevant" >> "${SCRIPT_LOG_FILE}"
    fi
fi

exit 0

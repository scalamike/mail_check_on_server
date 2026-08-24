#!/bin/bash

########################################
# CONFIGURATION
########################################

SERVER_IP=$(hostname -i)
DKIM_SELECTOR="default"

DOMAIN="$1"
MODE="$2"


########################################
# ALL DOMAINS
########################################

if [ "$DOMAIN" = "alldomains" ]; then

    if [ "$MODE" != "short" ] && [ "$MODE" != "full" ]; then
        echo "Usage:"
        echo "  $0 alldomains short"
        echo "  $0 alldomains full"
        exit 1
    fi

    while IFS= read -r domain; do
        [ -z "$domain" ] && continue

        "$0" "$domain" "$MODE"

        if [ "$MODE" = "full" ]; then
            echo
        fi

    done < /etc/localdomains

    exit 0
fi




if [ -z "$DOMAIN" ] || [ -z "$MODE" ]; then
    echo "Usage:"
    echo "  $0 domain short"
    echo "  $0 domain full"
    exit 1
fi

if [ "$MODE" != "short" ] && [ "$MODE" != "full" ]; then
    echo "Invalid option: $MODE"
    echo
    echo "Use:"
    echo "  short = Short summary"
    echo "  full  = Full details"
    exit 1
fi

########################################
# VARIABLES
########################################

DKIM_KEY="/var/spanel/domain_keys/public/$DOMAIN"

ISSUES=()

DKIM_STATUS="UNKNOWN"
SPF_STATUS="UNKNOWN"
MX_STATUS="UNKNOWN"

########################################
# DKIM CHECK
########################################

if [ ! -f "$DKIM_KEY" ]; then

    DKIM_STATUS="MISSING LOCAL KEY"
    ISSUES+=("DKIM local public key is missing: $DKIM_KEY")

else

    LOCAL_DKIM="v=DKIM1;k=rsa;p=$(sed \
        '/-----BEGIN PUBLIC KEY-----/d;
         /-----END PUBLIC KEY-----/d' \
        "$DKIM_KEY" | tr -d '[:space:]')"

    LOCAL_DKIM=$(echo "$LOCAL_DKIM" \
        | tr -d '[:space:]' \
        | sed 's/;$//')

    DKIM_RAW=$(dig +short TXT \
        "${DKIM_SELECTOR}._domainkey.${DOMAIN}")

    DKIM_RECORD_COUNT=$(printf '%s\n' "$DKIM_RAW" \
        | sed '/^[[:space:]]*$/d' \
        | wc -l)

    DNS_DKIM=$(printf '%s\n' "$DKIM_RAW" \
        | tr -d '"[:space:]' \
        | sed 's/;$//')

    if [ "$DKIM_RECORD_COUNT" -eq 0 ]; then

        DKIM_STATUS="MISSING"
        ISSUES+=("DKIM record is missing")

    elif [ "$DKIM_RECORD_COUNT" -gt 1 ]; then

        DKIM_STATUS="DUPLICATE"
        ISSUES+=("Multiple DKIM TXT records found")

    elif [ "$LOCAL_DKIM" = "$DNS_DKIM" ]; then

        DKIM_STATUS="VALID"

    else

        DKIM_STATUS="INVALID"
        ISSUES+=("DKIM DNS record does not match local public key")

    fi

fi


########################################
# SPF CHECK
########################################

SPF_RECORDS=$(dig +short TXT "$DOMAIN" \
    | sed 's/" "//g; s/^"//; s/"$//' \
    | grep '^v=spf1')

SPF_COUNT=$(printf '%s\n' "$SPF_RECORDS" \
    | sed '/^[[:space:]]*$/d' \
    | wc -l)

if [ "$SPF_COUNT" -eq 0 ]; then

    SPF_STATUS="MISSING"
    ISSUES+=("SPF record is missing")

elif [ "$SPF_COUNT" -gt 1 ]; then

    SPF_STATUS="DUPLICATE"
    ISSUES+=("Multiple SPF records found")

else

    SPF_RECORD=$(printf '%s\n' "$SPF_RECORDS" | head -1)

    if echo "$SPF_RECORD" \
        | grep -Eq "(^| )[+]?ip4:${SERVER_IP//./\\.}( |$)"; then

        SPF_STATUS="VALID"

    else

        SPF_STATUS="INVALID"
        ISSUES+=("SPF does not contain server IP $SERVER_IP")

    fi

fi

########################################
# MX CHECK
########################################

MX_RECORDS=$(dig +short MX "$DOMAIN")

MX_COUNT=$(printf '%s\n' "$MX_RECORDS" \
    | sed '/^[[:space:]]*$/d' \
    | wc -l)

MX_DUPLICATES=""

MX_DETAILS=()

MX_POINTS_TO_SERVER=0
MX_BAD_TARGET=0

if [ "$MX_COUNT" -eq 0 ]; then

    MX_STATUS="MISSING"
    ISSUES+=("MX record is missing")

else

    ########################################
    # Duplicate MX target check
    ########################################

    MX_DUPLICATES=$(echo "$MX_RECORDS" \
        | awk '{print $2}' \
        | sed 's/\.$//' \
        | sort \
        | uniq -d)

    if [ -n "$MX_DUPLICATES" ]; then

        ISSUES+=("Duplicate MX target found: $MX_DUPLICATES")

    fi

    ########################################
    # MX resolution check
    ########################################

    while read -r PRIORITY MX_HOST; do

        [ -z "$MX_HOST" ] && continue

        MX_HOST=${MX_HOST%.}

        MX_IPS=$(dig +short A "$MX_HOST")

        if echo "$MX_IPS" | grep -qx "$SERVER_IP"; then

            MX_POINTS_TO_SERVER=1

            MX_DETAILS+=(
                "$PRIORITY|$MX_HOST|$MX_IPS|POINTS TO SERVER"
            )

        else

            MX_BAD_TARGET=1

            MX_DETAILS+=(
                "$PRIORITY|$MX_HOST|$MX_IPS|DOES NOT POINT TO SERVER"
            )

            if [ -z "$MX_IPS" ]; then
                ISSUES+=("MX $MX_HOST does not resolve to an IPv4 address")
            else
                ISSUES+=("MX $MX_HOST resolves to $MX_IPS instead of $SERVER_IP")
            fi

        fi

    done <<< "$MX_RECORDS"

    if [ "$MX_BAD_TARGET" -eq 1 ]; then

        MX_STATUS="INVALID"

    elif [ -n "$MX_DUPLICATES" ]; then

        MX_STATUS="DUPLICATE"

    elif [ "$MX_POINTS_TO_SERVER" -eq 1 ]; then

        MX_STATUS="VALID"

    else

        MX_STATUS="INVALID"

    fi

fi


########################################
# OPTION 1 - SHORT SUMMARY
########################################

if [ "$MODE" = "short" ]; then

    if [ "${#ISSUES[@]}" -eq 0 ]; then

        echo "$DOMAIN -> OK"

    else

        echo "$DOMAIN -> ISSUE"

        for ISSUE in "${ISSUES[@]}"; do
            echo "  - $ISSUE"
        done

    fi

    exit 0

fi


########################################
# OPTION 2 - FULL DETAILS
########################################

echo "======================================"
echo " DNS CHECK FOR: $DOMAIN"
echo " SERVER IP:     $SERVER_IP"
echo "======================================"
echo


########################################
# DKIM DETAILS
########################################

echo "===== DKIM CHECK ====="

echo "Status: $DKIM_STATUS"
echo "Selector: $DKIM_SELECTOR"

if [ -f "$DKIM_KEY" ]; then

    echo "Local key:"
    echo "$LOCAL_DKIM"

    echo
    echo "DNS record:"

    if [ -n "$DNS_DKIM" ]; then
        echo "$DNS_DKIM"
    else
        echo "NONE"
    fi

else

    echo "Local key file:"
    echo "$DKIM_KEY"
    echo "NOT FOUND"

fi


########################################
# SPF DETAILS
########################################

echo
echo "===== SPF CHECK ====="

echo "Status: $SPF_STATUS"

if [ "$SPF_COUNT" -eq 0 ]; then

    echo "DNS: NONE"

else

    echo "DNS:"
    echo "$SPF_RECORDS"

fi

echo
echo "Required mechanisms:"
echo "  ip4:$SERVER_IP"
echo "  a"
echo "  mx"
echo "  ~all"


########################################
# MX DETAILS
########################################

echo
echo "===== MX CHECK ====="

echo "Status: $MX_STATUS"

if [ "$MX_COUNT" -eq 0 ]; then

    echo "MX records: NONE"

else

    echo "MX records:"
    echo "$MX_RECORDS"

    echo

    if [ -n "$MX_DUPLICATES" ]; then
        echo "Duplicate MX targets:"
        echo "$MX_DUPLICATES"
    else
        echo "Duplicate MX targets: NONE"
    fi

    echo

    for DETAIL in "${MX_DETAILS[@]}"; do

        IFS='|' read -r PRIORITY HOST IPS STATUS <<< "$DETAIL"

        echo "MX: $PRIORITY $HOST"

        if [ -n "$IPS" ]; then
            echo "Resolves to: $IPS"
        else
            echo "Resolves to: NONE"
        fi

        echo "Status: $STATUS"
        echo

    done

fi


########################################
# FINAL RESULT
########################################

echo "======================================"

if [ "${#ISSUES[@]}" -eq 0 ]; then

    echo "$DOMAIN -> OK"

else

    echo "$DOMAIN -> ISSUE"

    for ISSUE in "${ISSUES[@]}"; do
        echo "  - $ISSUE"
    done

fi

echo "======================================"

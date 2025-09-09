#!/bin/bash
#
# This scripts will generate a list of CIDR prefixes
# being advertised by the provided AS Number.
#
# The output will be saved to the current directory
#
# Some parameters set below, along with debugging info.
#
OUTPUT_DIR="."            # default to current directory
DEVICE_GROUP="External"   # Your device group, this is used in the commands
TAG="ASN_Blocks"          # A tag to add to the objects and group  
CUSTOM_OBJ_PREFIX="2025_" # A prefix which is added to all objects
WT_HEIGHT=10              # Height that whiptail will use
WT_WIDTH=60               # Width that whiptail will use
DEBUG=false               # Enable debugging if required true|false
DEBUG_LOG="./debug.log"   # Debug Filename/location

###############################################
# --- Set Whiptail for common appearance
###############################################
export NEWT_COLORS='
window=,lightgray
title=red,lightgray
border=black,lightgray
textbox=black,lightgray
button=lightgray,red
'

###############################################
# Debug 
###############################################
debug() {
    if [ "$DEBUG" = true ]; then
        local caller="${FUNCNAME[1]:-MAIN}"   # MAIN if not called from a function
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$caller] $*" >> "$DEBUG_LOG"
    fi
}


###############################################
# Exit script gracefully
###############################################
quit_script() {
    debug "script exit called"
    debug "$*"
    echo " "
    echo "Terminated: $*"
    echo " "
    exit 1
}


###############################################
# Main Script Below Here
###############################################
if [ -z "$1" ]
    then

        # --- Initial Script msg and confirmation
        #######################################
        debug " "
        debug "Script Starting"
        debug "Initial message and confirmation"
        DIALOGUE_TEXT="This utility will generate the Palo Alto cli commands to add Network Objects for a specified ASN.\\n\\nDo you wish to proceed?"
        CONFIRMATION=$(whiptail --title "ASN to Palo Objects." \
            --yesno "$DIALOGUE_TEXT" $WT_HEIGHT $WT_WIDTH \
            --title "ASN to Palo Objets." 3>&1 1>&2 2>&3; echo $?)

        if [ $CONFIRMATION -eq "1" ] ;then
            quit_script "No files have been created or changed."
            debug "Script exiting after user cancellation"
        fi
        debug "Script proceeding"


        # --- Requested ASN
        #######################################
        debug "Requesting ASN dialogue"
        ASN=$(whiptail --title "ASN to Palo Objects." --inputbox "Please provide the required ASN, (numbic value 1 - 64495):" \
            $WT_HEIGHT $WT_WIDTH 3>&1 1>&2 2>&3)
        if [[ "$ASN" =~ ^[0-9]+$ ]] && (( ASN >= 1 && ASN <= 64495 )); then
            debug "Requested ASN appears to be valid"
        else
            debug "Requested ASN appears to be invalid - script will exit"
            whiptail --title " INVALID INPUT " --msgbox "ASN must be in the range 1 - 64495." \
                 --ok-button "Quit" $WT_HEIGHT $WT_WIDTH \
                 3>&1 1>&2 2>&3
            quit_script "Error, ASN input was invalid."
        fi
        debug "Requested ASN = $ASN"

        clear
        echo " "
        echo "Please wait, currently downloading information for ASN $ASN."

        # --- Fetch CIDR for specified ASN
        #######################################
        TIMESTAMP=$(date +"%Y%m%d-%H%M")
        debug "ASN=$ASN, TIMESTAMP=$TIMESTAMP, fetching data"

        # --- Fetch prefix data ---
        #######################################
        DATA=$(curl -s -f "https://api.bgpview.io/asn/$ASN/prefixes")
        if [ $? -ne 0 ] || [ -z "$DATA" ]; then
            quit_script "Error: Failed to fetch prefix data from BGPView API."
        fi

        STATUS=$(echo "$DATA" | jq -r '.status')
        if [ "$STATUS" != "ok" ]; then
            quit_script "Error: ASN${ASN_NUM} not found in BGPView."
        fi
        debug "ASN $ASN found in BGPview, prefixes downloaded"

        debug "# --- Fetch ASN info for the name ---"
        ASN_INFO=$(curl -s -f "https://api.bgpview.io/asn/$ASN")
        if [ $? -ne 0 ] || [ -z "$ASN_INFO" ]; then
            quit_script "Error: Failed to fetch ASN info."
        fi
        debug "ASN Named Operator = $ASN_INFO"

        # --- Generate filename for saving info
        #######################################
        ASN_NAME_RAW=$(echo "$ASN_INFO" | jq -r '.data.name')
        ASN_NAME_SAFE=$(echo "$ASN_NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed -E 's/ /_/g; s/[^a-z0-9_]//g')
    
        # --- Defaults if missing
        #######################################
        [ -z "$ASN_NAME_RAW" ] || [ "$ASN_NAME_RAW" = "null" ] && ASN_NAME_RAW="Unknown"
        [ -z "$ASN_NAME_SAFE" ] && ASN_NAME_SAFE="asn${ASN_NUM}"
        debug "Found ASN${ASN} - ${ASN_NAME_RAW}, generating filenames"

        # --- Allocating Filenames
        #######################################
        FILE_V4="${OUTPUT_DIR}/${ASN_NAME_SAFE}_as${ASN}_ipv4_${TIMESTAMP}.txt"
        FILE_V6="${OUTPUT_DIR}/${ASN_NAME_SAFE}_as${ASN}_ipv6_${TIMESTAMP}.txt"

        # --- Dumping IPv4 prefixes to file
        #######################################
        echo "$DATA" | jq -r '.data.ipv4_prefixes[].prefix' > "$FILE_V4"
        if [ -s "$FILE_V4" ]; then
            debug "Saved IPv4 prefixes → $FILE_V4"
        else
            debug "No IPv4 prefixes found."
            rm -f "$FILE_V4"
            quit_script "No IPv4 prefixes found"
        fi

        # --- Dumping IPv6 prefixes to file
        #######################################
        echo "$DATA" | jq -r '.data.ipv6_prefixes[].prefix' > "$FILE_V6"
        if [ -s "$FILE_V6" ]; then
            debug "Saved IPv6 prefixes → $FILE_V6"
        else
            debug "No IPv6 prefixes found."
            rm -f "$FILE_V6"
        fi

        if [[ -s $FILE_V4 || -s $FILE_V6 ]]; then
            DIALOGUE_TEXT="CIDR prefixes found and saved for further processing."
            debug $DIALOGUE_TEXT
            #whiptail --title "ASN to Palo Objects." --msgbox "$DIALOGUE_TEXT" \
            #    $WT_HEIGHT $WT_WIDTH --no-button "Cancel" --yes-button "OK" 3>&1 1>&2 2>&3
        fi



        # --- Generate Output for the ASN
        #######################################
        debug "Requesting Description for ASN$ASN objects"
        COMMENT=$(whiptail --inputbox "Please provide text for the description, who requested this, and ticket reference etc:" \
                  --title "ASN to Palo Objects." $WT_HEIGHT $WT_WIDTH "Requsted By " 3>&1 1>&2 2>&3)

        INPUT_FILE=$FILE_V4
        OUTPUT_FILE=${INPUT_FILE/.txt/.commands.txt}
        PREFIX="ASN$ASN"

        echo "### CLI commands for device-group: $DEVICE_GROUP ###">$OUTPUT_FILE
        echo " " >>$OUTPUT_FILE
        echo "### Preparing Panorama to accept scripting" >>$OUTPUT_FILE
        echo "### commands to paste are below here" >>$OUTPUT_FILE
        echo " " >>$OUTPUT_FILE
        echo "set cli config-output-format set" >>$OUTPUT_FILE
        echo "set cli scripting-mode on" >>$OUTPUT_FILE
        echo "configure" >>$OUTPUT_FILE
        echo " " >>$OUTPUT_FILE

        # Create address objects
        #######################################
        while IFS= read -r CIDR; do
            # skip blank lines
            [[ -z "$CIDR" ]] && continue

            IP="${CIDR%%/*}"
            MASK="${CIDR##*/}"
            NAME="${IP//./_}-$MASK"
            OBJ_NAME="$CUSTOM_OBJ_PREFIX${PREFIX}-${NAME}"
            GRP_NAME="$CUSTOM_OBJ_PREFIX$PREFIX"

            echo "set device-group $DEVICE_GROUP address $OBJ_NAME ip-netmask $CIDR" >> $OUTPUT_FILE
            echo "set device-group $DEVICE_GROUP address $OBJ_NAME tag $TAG" >> $OUTPUT_FILE
            echo "set device-group $DEVICE_GROUP address $OBJ_NAME description \"$COMMENT\"" >> $OUTPUT_FILE
            echo "set device-group $DEVICE_GROUP address $OBJ_NAME disable-override no" >> $OUTPUT_FILE
            echo "set device-group $DEVICE_GROUP address-group $GRP_NAME static [ $OBJ_NAME ]" >> $OUTPUT_FILE

            #debug "set device-group $DEVICE_GROUP address $OBJ_Name ip-netmask $cidr"

            # Collect names for group membership
            GRP_ITEMS+=("$OBJ_NAME")
        done < "$INPUT_FILE"
         
        echo " " >>$OUTPUT_FILE
        echo "### end of config commands." >>$OUTPUT_FILE
        echo " " >>$OUTPUT_FILE
        echo "commit" >>$OUTPUT_FILE
        echo " " >>$OUTPUT_FILE
        echo "exit" >>$OUTPUT_FILE
        echo "set cli config-output-format default" >>$OUTPUT_FILE
        echo "set cli scripting-mode off" >>$OUTPUT_FILE
        echo " " >>$OUTPUT_FILE
        echo "exit" >>$OUTPUT_FILE
        debug "$GRP_NAME Object group generated for ${#GRP_ITEMS[@]} prefixes."

        # --- Output some results
        #######################################
        DIALOGUE_TEXT="Palo Alto command line script generated for ASN $ASN.\\n\\n${#GRP_ITEMS[@]} prefixes are included in object group $GRP_NAME."
        whiptail --title "ASN to Palo Objects." \
            --msgbox "$DIALOGUE_TEXT" $WT_HEIGHT $WT_WIDTH \
            --title "ASN to Palo Objets." 3>&1 1>&2 2>&3
        echo " "
        echo "The Panorama config file has been sved as $OUTPUT_FILE"
        echo " "
        echo "To view the file:"
        echo " "
        echo "  cat $OUTPUT_FILE"
        echo " "
    else
        quit_script "Error, Script does not accept any parameters!"
    fi

exit 0

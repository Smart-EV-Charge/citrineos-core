#!/bin/sh
# SPDX-FileCopyrightText: 2025 Contributors to the CitrineOS Project
#
# SPDX-License-Identifier: Apache-2.0

CHARGE_POINT_ID="${EVEREST_CHARGE_POINT_ID:-cp001}"
CHARGE_POINT_ID_EXPLICIT="false"

if [ -n "$EVEREST_CHARGE_POINT_ID" ]; then
    CHARGE_POINT_ID_EXPLICIT="true"
fi

/entrypoint.sh
http-server /tmp/everest_ocpp_logs -p 8888 &

if [ "$OCPP_VERSION" = "one" ]; then
    TARGET_URL_ONE_SIX="$EVEREST_TARGET_URL"

    if [ -n "$TARGET_URL_ONE_SIX" ] && [ "$CHARGE_POINT_ID_EXPLICIT" = "true" ]; then
        TARGET_URL_ONE_SIX="${TARGET_URL_ONE_SIX%/}"
        case "$TARGET_URL_ONE_SIX" in
            */"$CHARGE_POINT_ID")
                ;;
            *)
                TARGET_URL_ONE_SIX="${TARGET_URL_ONE_SIX}/${CHARGE_POINT_ID}"
                ;;
        esac
    fi

    chmod +x /ext/build/run-scripts/run-sil-ocpp.sh
    sed -i "0,/127.0.0.1:8180\/steve\/websocket\/CentralSystemService\// s|127.0.0.1:8180/steve/websocket/CentralSystemService/|${TARGET_URL_ONE_SIX}|" /ext/dist/share/everest/modules/OCPP/config-docker.json
    if [ -n "$TARGET_URL_ONE_SIX" ]; then
        case "$TARGET_URL_ONE_SIX" in
            wss://*)
                sed -i 's/"SecurityProfile": [0-9]\+/"SecurityProfile": 2/' /ext/dist/share/everest/modules/OCPP/config-docker.json
                ;;
            ws://*)
                sed -i 's/"SecurityProfile": [0-9]\+/"SecurityProfile": 1/' /ext/dist/share/everest/modules/OCPP/config-docker.json
                ;;
        esac
    fi
    if [ "$EVEREST_DISABLE_ISO15118" = "true" ]; then
        awk '
        BEGIN { skip_module = 0; skip_hlc = 0 }
        {
            if ($0 ~ /^  iso15118_charger:/) {
                skip_module = 1
                next
            }

            if (skip_module == 1) {
                if ($0 ~ /^  [A-Za-z0-9_]+:/) {
                    skip_module = 0
                } else {
                    next
                }
            }

            if ($0 ~ /^      hlc:/) {
                skip_hlc = 1
                next
            }

            if (skip_hlc == 1) {
                if ($0 ~ /^      [A-Za-z0-9_]+:/ || $0 ~ /^  [A-Za-z0-9_]+:/) {
                    skip_hlc = 0
                } else {
                    next
                }
            }

            print
        }
        ' /ext/source/config/config-sil-ocpp.yaml > /tmp/config-sil-ocpp-noiso15118.yaml

        LD_LIBRARY_PATH=/ext/dist/lib:$LD_LIBRARY_PATH \
        PATH=/ext/dist/bin:$PATH \
        manager \
            --prefix /ext/dist \
            --conf /tmp/config-sil-ocpp-noiso15118.yaml
    else
        /ext/build/run-scripts/run-sil-ocpp.sh
    fi
else
    if ! command -v sqlite3 >/dev/null 2>&1; then
        apt-get update && apt-get install -y sqlite3
    fi

    INTERNAL_CTRLR_CONFIG="/ext/dist/share/everest/modules/OCPP201/component_config/standardized/InternalCtrlr.json"
    SECURITY_CTRLR_CONFIG="/ext/dist/share/everest/modules/OCPP201/component_config/standardized/SecurityCtrlr.json"

    if [ -f "$INTERNAL_CTRLR_CONFIG" ]; then
        sed -i "s/\"cp001\"/\"$CHARGE_POINT_ID\"/g" "$INTERNAL_CTRLR_CONFIG"
    fi

    if [ -f "$SECURITY_CTRLR_CONFIG" ]; then
        sed -i "s/\"cp001\"/\"$CHARGE_POINT_ID\"/g" "$SECURITY_CTRLR_CONFIG"
    fi

    sqlite3 /ext/dist/share/everest/modules/OCPP201/device_model_storage.db \
            "UPDATE VARIABLE_ATTRIBUTE \
            SET value = '[{\"configurationSlot\": 1, \"connectionData\": {\"messageTimeout\": 30, \"ocppCsmsUrl\": \"$EVEREST_TARGET_URL\", \"ocppInterface\": \"Wired0\", \"ocppTransport\": \"JSON\", \"ocppVersion\": \"OCPP20\", \"securityProfile\": 1}},{\"configurationSlot\": 2, \"connectionData\": {\"messageTimeout\": 30, \"ocppCsmsUrl\": \"$EVEREST_TARGET_URL\", \"ocppInterface\": \"Wired0\", \"ocppTransport\": \"JSON\", \"ocppVersion\": \"OCPP20\", \"securityProfile\": 1}}]' \
            WHERE \
            variable_Id IN ( \
            SELECT id FROM VARIABLE \
            WHERE name = 'NetworkConnectionProfiles' \
            );"

    sqlite3 /ext/dist/share/everest/modules/OCPP201/device_model_storage.db \
            "UPDATE VARIABLE_ATTRIBUTE \
            SET value = '$CHARGE_POINT_ID' \
            WHERE \
            variable_Id IN ( \
            SELECT id FROM VARIABLE \
            WHERE name = 'ChargePointId' \
            );"

    if [ "$EVEREST_ENABLE_PNC" = "true" ]; then
        rm /ext/dist/share/everest/modules/OCPP201/component_config/custom/EVSE_2.json
        rm /ext/dist/share/everest/modules/OCPP201/component_config/custom/Connector_2_1.json
        chmod +x /ext/build/run-scripts/run-sil-ocpp201-pnc.sh
        /ext/build/run-scripts/run-sil-ocpp201-pnc.sh
    else
        chmod +x /ext/build/run-scripts/run-sil-ocpp201.sh
        /ext/build/run-scripts/run-sil-ocpp201.sh
    fi
fi
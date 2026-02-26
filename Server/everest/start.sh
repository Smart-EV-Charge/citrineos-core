#!/bin/sh
# SPDX-FileCopyrightText: 2025 Contributors to the CitrineOS Project
#
# SPDX-License-Identifier: Apache-2.0

if [ "$OCPP_VERSION" = "two" ]; then
    apt-get update && apt-get install -y sqlite3
    sqlite3 /ext/dist/share/everest/modules/OCPP201/device_model_storage.db \
            "UPDATE VARIABLE_ATTRIBUTE \
            SET value = '[{\"configurationSlot\": 1, \"connectionData\": {\"messageTimeout\": 30, \"ocppCsmsUrl\": \"$EVEREST_TARGET_URL\", \"ocppInterface\": \"Wired0\", \"ocppTransport\": \"JSON\", \"ocppVersion\": \"OCPP20\", \"securityProfile\": 1}},{\"configurationSlot\": 2, \"connectionData\": {\"messageTimeout\": 30, \"ocppCsmsUrl\": \"$EVEREST_TARGET_URL\", \"ocppInterface\": \"Wired0\", \"ocppTransport\": \"JSON\", \"ocppVersion\": \"OCPP20\", \"securityProfile\": 1}}]' \
            WHERE \
            variable_Id IN ( \
            SELECT id FROM VARIABLE \
            WHERE name = 'NetworkConnectionProfiles' \
            );"
fi

/entrypoint.sh
http-server /tmp/everest_ocpp_logs -p 8888 &

if [ "$OCPP_VERSION" = "one" ]; then
    chmod +x /ext/build/run-scripts/run-sil-ocpp.sh
    sed -i "0,/127.0.0.1:8180\/steve\/websocket\/CentralSystemService\// s|127.0.0.1:8180/steve/websocket/CentralSystemService/|${EVEREST_TARGET_URL}|" /ext/dist/share/everest/modules/OCPP/config-docker.json
    if [ "$EVEREST_DISABLE_ISO15118" = "true" ]; then
        awk '
        BEGIN { skip = 0 }
        {
            if ($0 ~ /^  iso15118_charger:/) {
                skip = 1
                next
            }

            if (skip == 1) {
                if ($0 ~ /^  [A-Za-z0-9_]+:/) {
                    skip = 0
                } else {
                    next
                }
            }

            if ($0 ~ /module_id: iso15118_charger/) {
                next
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
    rm /ext/dist/share/everest/modules/OCPP201/component_config/custom/EVSE_2.json
    rm /ext/dist/share/everest/modules/OCPP201/component_config/custom/Connector_2_1.json
    if [ "$EVEREST_ENABLE_PNC" = "true" ]; then
        chmod +x /ext/build/run-scripts/run-sil-ocpp201-pnc.sh
        /ext/build/run-scripts/run-sil-ocpp201-pnc.sh
    else
        chmod +x /ext/build/run-scripts/run-sil-ocpp201.sh
        /ext/build/run-scripts/run-sil-ocpp201.sh
    fi
fi
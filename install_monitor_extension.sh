#!/bin/bash

# ******INSTALADOR DE MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******
# /* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>
#  * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>
# Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante

echo "******INSTALADOR DE MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******"
echo "/* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>"
echo " * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>"
echo "Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante"
echo ""
sleep 10

# Verificar si se ejecuta como root
if [ "$(id -u)" != "0" ]; then
    echo "Este script debe ejecutarse como root. Usa sudo."
    exit 1
fi

# Extraer credenciales de /etc/freepbx.conf
if [ -f /etc/freepbx.conf ]; then
    MYSQL_USER=$(grep 'AMPDBUSER' /etc/freepbx.conf | sed -n "s/.*AMPDBUSER.*=.*\"\(.*\)\";.*/\1/p")
    MYSQL_PASS=$(grep 'AMPDBPASS' /etc/freepbx.conf | sed -n "s/.*AMPDBPASS.*=.*\"\(.*\)\";.*/\1/p")
    MYSQL_DB=$(grep 'AMPDBNAME' /etc/freepbx.conf | sed -n "s/.*AMPDBNAME.*=.*\"\(.*\)\";.*/\1/p")
else
    echo "No se encontró el archivo /etc/freepbx.conf."
    exit 1
fi

if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ] || [ -z "$MYSQL_DB" ]; then
    echo "No se pudieron extraer las credenciales de la base de datos."
    exit 1
fi

mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -D"$MYSQL_DB" -e "SELECT 1" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    if [ -f /etc/asterisk/freepbx.conf ]; then
        MYSQL_USER=$(grep 'AMPDBUSER' /etc/asterisk/freepbx.conf | sed -n "s/.*AMPDBUSER.*=.*\"\(.*\)\";.*/\1/p")
        MYSQL_PASS=$(grep 'AMPDBPASS' /etc/asterisk/freepbx.conf | sed -n "s/.*AMPDBPASS.*=.*\"\(.*\)\";.*/\1/p")
        MYSQL_DB=$(grep 'AMPDBNAME' /etc/asterisk/freepbx.conf | sed -n "s/.*AMPDBNAME.*=.*\"\(.*\)\";.*/\1/p")
        mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -D"$MYSQL_DB" -e "SELECT 1" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "No se pudo conectar a la base de datos."
            exit 1
        fi
    else
        echo "No se pudo conectar a la base de datos."
        exit 1
    fi
fi

# Copiar el script principal
cat > /usr/local/bin/monitor_extension.sh << 'EOF'
#!/bin/bash

# ******MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******
# /* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>
#  * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>
# Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante

STATE_FILE="/tmp/extension_status.txt"
MYSQL_USER="MYSQL_USER_VALUE"
MYSQL_PASS="MYSQL_PASS_VALUE"
MYSQL_DB="MYSQL_DB_VALUE"
LOG_FILE="/var/log/monitor_extension.log"
ASTERISK="/usr/sbin/asterisk"
MYSQL="/usr/bin/mysql"
SENDMAIL="/usr/sbin/sendmail"

encode_subject() {
    subject="$1"
    echo "=?UTF-8?B?$(echo -n "$subject" | base64)?="
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

get_user_info() {
    extension=$1
    result=$($MYSQL -u$MYSQL_USER -p$MYSQL_PASS -D$MYSQL_DB -N -e "SELECT email, displayname, fname, lname FROM userman_users WHERE default_extension = '$extension'" 2>>"$LOG_FILE")
    if [ $? -ne 0 ]; then
        log "Error al conectar a la base de datos para la extensi&oacute;n $extension"
        echo ""
        return 1
    fi
    email=$(echo "$result" | awk '{print $1}')
    displayname=$(echo "$result" | awk '{print $2}')
    fname=$(echo "$result" | awk '{print $3}')
    lname=$(echo "$result" | awk '{print $4}')
    
    if [ -n "$displayname" ] && [ "$displayname" != "NULL" ]; then
        name="$displayname"
    elif [ -n "$fname" ] && [ "$fname" != "NULL" ]; then
        name="$fname $lname"
    else
        name="Usuario"
    fi

    if [ -n "$email" ]; then
        echo "$email|$name"
    else
        echo ""
    fi
}

SMTP_FROM="Tu servicio de telefon&iacute;a AJTEL <soporte@ajtel.net>"

[ ! -f "$STATE_FILE" ] && touch "$STATE_FILE"
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

while true; do
    $ASTERISK -rx 'sip show peers' 2>>"$LOG_FILE" | grep -E '^[0-9]+/' | while read -r line; do
        extension=$(echo "$line" | awk '{print $1}' | cut -d'/' -f1)
        ip=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $8}' | grep -E '^(OK|UNREACHABLE|UNKNOWN)$' || echo "$line" | awk '{print $9}' | grep -E '^(OK|UNREACHABLE|UNKNOWN)$' || echo "UNKNOWN")
        prev_status=$(grep "^$extension " "$STATE_FILE" | awk '{print $2}' || echo "UNKNOWN")

        if [ "$status" != "$prev_status" ]; then
            user_info=$(get_user_info "$extension")
            email=$(echo "$user_info" | cut -d'|' -f1)
            name=$(echo "$user_info" | cut -d'|' -f2)
            if [ -n "$email" ]; then
                if [ "$status" = "UNREACHABLE" ] || [ "$status" = "UNKNOWN" ] || [ "$ip" = "(Unspecified)" ]; then
                    subject=$(encode_subject "Tel&eacute;fono N&uacute;mero $extension Desconectado")
                    message='From: '"$SMTP_FROM"'\nTo: '"$email"'\nSubject: '"$subject"'\nContent-Type: text/plain; charset=UTF-8\n\nEstimado/a '"$name"',\n\nHemos detectado que el tel&eacute;fono n&uacute;mero '"$extension"' no est&aacute; conectado a la red. Le recomendamos verificar su conexi&oacute;n para evitar interrupciones en la recepci&oacute;n de llamadas.\n\nAtentamente,\nTu servicio de telefon&iacute;a AJTEL\nContacto: soporte@ajtel.net | Tel: +52 (55) 8526-5050 o *511 desde tu l&iacute;nea'
                    echo -e "$message" | $SENDMAIL -t 2>>"$LOG_FILE"
                elif [ "$status" = "OK" ]; then
                    subject=$(encode_subject "Tel&eacute;fono N&uacute;mero $extension Reconectado")
                    message='From: '"$SMTP_FROM"'\nTo: '"$email"'\nSubject: '"$subject"'\nContent-Type: text/plain; charset=UTF-8\n\nEstimado/a '"$name"',\n\nNos complace informarle que el tel&eacute;fono n&uacute;mero '"$extension"' se ha reconectado exitosamente a la red. Ahora puede realizar y recibir llamadas con normalidad.\n\nAtentamente,\nTu servicio de telefon&iacute;a AJTEL\nContacto: soporte@ajtel.net | Tel: +52 (55) 8526-5050 o *511 desde tu l&iacute;nea'
                    echo -e "$message" | $SENDMAIL -t 2>>"$LOG_FILE"
                fi
            fi
        fi

        grep -v "^$extension " "$STATE_FILE" > /tmp/state_tmp.txt
        echo "$extension $status" >> /tmp/state_tmp.txt
        mv /tmp/state_tmp.txt "$STATE_FILE" 2>>"$LOG_FILE"
    done
    sleep 60
done
EOF

sed -i "s/MYSQL_USER_VALUE/$MYSQL_USER/" /usr/local/bin/monitor_extension.sh
sed -i "s/MYSQL_PASS_VALUE/$MYSQL_PASS/" /usr/local/bin/monitor_extension.sh
sed -i "s/MYSQL_DB_VALUE/$MYSQL_DB/" /usr/local/bin/monitor_extension.sh

chmod +x /usr/local/bin/monitor_extension.sh
touch /var/log/monitor_extension.log
chmod 644 /var/log/monitor_extension.log

# Copiar el archivo de servicio systemd
cat > /etc/systemd/system/monitor_extension.service << 'EOF'
[Unit]
Description=Monitor FreePBX Extension Status
After=network.target

[Service]
ExecStart=/usr/local/bin/monitor_extension.sh
Restart=always
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
StandardOutput=append:/var/log/monitor_extension.log
StandardError=append:/var/log/monitor_extension.log

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/monitor_extension.service
systemctl daemon-reload
systemctl enable monitor_extension.service
systemctl start monitor_extension.service

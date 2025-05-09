#!/bin/bash

# Establecer codificación UTF-8 para la consola
export LC_ALL=es_MX.utf8

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

echo "Paso 1: Verificando si se ejecuta como root..."
# Verificar si se ejecuta como root
if [ "$(id -u)" != "0" ]; then
    echo "Error: Este script debe ejecutarse como root. Usa sudo."
    exit 1
fi
echo "Paso 1 completado: Script ejecut&aacute;ndose como root."

echo "Paso 2: Extrayendo credenciales de /etc/freepbx.conf..."
# Extraer credenciales de /etc/freepbx.conf
if [ -f /etc/freepbx.conf ]; then
    MYSQL_USER=$(grep 'AMPDBUSER' /etc/freepbx.conf | sed -n "s/.*AMPDBUSER.*=.*\"\(.*\)\";.*/\1/p")
    MYSQL_PASS=$(grep 'AMPDBPASS' /etc/freepbx.conf | sed -n "s/.*AMPDBPASS.*=.*\"\(.*\)\";.*/\1/p")
    MYSQL_DB=$(grep 'AMPDBNAME' /etc/freepbx.conf | sed -n "s/.*AMPDBNAME.*=.*\"\(.*\)\";.*/\1/p")
else
    echo "Error: No se encontr&oacute; el archivo /etc/freepbx.conf."
    exit 1
fi

if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ] || [ -z "$MYSQL_DB" ]; then
    echo "Error: No se pudieron extraer las credenciales de la base de datos."
    exit 1
fi
echo "Paso 2 completado: Credenciales extra&iacute;das - MYSQL_USER=$MYSQL_USER, MYSQL_DB=$MYSQL_DB"

echo "Paso 3: Probando conexi&oacute;n a la base de datos..."
# Probar la conexión a la base de datos
echo "Probando conexi&oacute;n a la base de datos con usuario $MYSQL_USER y base de datos $MYSQL_DB..."
mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -D"$MYSQL_DB" -e "SELECT 1"
if [ $? -ne 0 ]; then
    echo "Conexi&oacute;n fallida con las credenciales extra&iacute;das. Intentando otras fuentes..."
    if [ -f /etc/asterisk/freepbx.conf ]; then
        MYSQL_USER=$(grep 'AMPDBUSER' /etc/asterisk/freepbx.conf | sed -n "s/.*AMPDBUSER.*=.*\"\(.*\)\";.*/\1/p")
        MYSQL_PASS=$(grep 'AMPDBPASS' /etc/asterisk/freepbx.conf | sed -n "s/.*AMPDBPASS.*=.*\"\(.*\)\";.*/\1/p")
        MYSQL_DB=$(grep 'AMPDBNAME' /etc/asterisk/freepbx.conf | sed -n "s/.*AMPDBNAME.*=.*\"\(.*\)\";.*/\1/p")
        echo "Probando conexi&oacute;n a la base de datos con usuario $MYSQL_USER y base de datos $MYSQL_DB..."
        mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -D"$MYSQL_DB" -e "SELECT 1"
        if [ $? -ne 0 ]; then
            echo "Error: No se pudo conectar a la base de datos."
            exit 1
        fi
    else
        echo "Error: No se pudo conectar a la base de datos y no se encontr&oacute; /etc/asterisk/freepbx.conf."
        exit 1
    fi
fi
echo "Paso 3 completado: Conexi&oacute;n a la base de datos exitosa."

echo "Paso 4: Copiando el script principal..."
# Copiar el script principal
cat > /usr/local/bin/monitor_extension.sh << 'EOF'
#!/bin/bash

# Establecer codificación UTF-8 para el script
export LC_ALL=es_MX.utf8

# ******MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******
# /* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>
#  * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>
# Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante

STATE_FILE="/tmp/extension_status.txt"
MYSQL_USER="freepbxuser"
MYSQL_PASS="Lqcgh/Ijd/re"
MYSQL_DB="asterisk"
LOG_FILE="/var/log/monitor_extension.log"
ERROR_LOG="/var/log/monitor_extension_error.log"
ASTERISK="/usr/sbin/asterisk"
MYSQL="/usr/bin/mysql"
SENDMAIL="/usr/sbin/sendmail"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

error_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$ERROR_LOG"
}

log "Script iniciado."

# Verificar si Asterisk está disponible
log "Verificando disponibilidad de Asterisk..."
if ! $ASTERISK -rx 'core show version' >/dev/null 2>>"$ERROR_LOG"; then
    error_log "Error: No se pudo conectar a Asterisk. Verifica que el servicio est&eacute; corriendo."
    exit 1
fi
log "Asterisk est&aacute; disponible."

encode_subject() {
    subject="$1"
    log "Codificando asunto: $subject"
    echo "=?UTF-8?B?$(echo -n "$subject" | base64)?="
}

get_user_info() {
    extension=$1
    log "Obteniendo informaci&oacute;n para la extensi&oacute;n $extension"
    result=$($MYSQL -u$MYSQL_USER -p$MYSQL_PASS -D$MYSQL_DB -N -e "SELECT email, displayname, fname, lname FROM userman_users WHERE default_extension = '$extension'" 2>>"$ERROR_LOG")
    if [ $? -ne 0 ]; then
        error_log "Error al conectar a la base de datos para la extensi&oacute;n $extension"
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
        log "Informaci&oacute;n obtenida para extensi&oacute;n $extension: email=$email, name=$name"
        echo "$email|$name"
    else
        log "No se encontr&oacute; email para extensi&oacute;n $extension"
        echo ""
    fi
}

SMTP_FROM="Tu servicio de telefon&iacute;a AJTEL <soporte@ajtel.net>"

log "Inicializando archivos de estado y log."
[ ! -f "$STATE_FILE" ] && touch "$STATE_FILE"
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
[ ! -f "$ERROR_LOG" ] && touch "$ERROR_LOG"

while true; do
    log "Iniciando ciclo de monitoreo."
    $ASTERISK -rx 'sip show peers' 2>>"$ERROR_LOG" | grep -E '^[0-9]+/' | while read -r line; do
        log "Procesando l&iacute;nea: $line"
        extension=$(echo "$line" | awk '{print $1}' | cut -d'/' -f1)
        ip=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $8}' | grep -E '^(OK|UNREACHABLE|UNKNOWN)$' || echo "$line" | awk '{print $9}' | grep -E '^(OK|UNREACHABLE|UNKNOWN)$' || echo "UNKNOWN")
        prev_status=$(grep "^$extension " "$STATE_FILE" | awk '{print $2}' || echo "UNKNOWN")
        log "Extensi&oacute;n $extension: IP=$ip, Estado actual=$status, Estado anterior=$prev_status"

        if [ "$status" != "$prev_status" ]; then
            log "Estado cambiado para extensi&oacute;n $extension, obteniendo informaci&oacute;n del usuario."
            user_info=$(get_user_info "$extension")
            email=$(echo "$user_info" | cut -d'|' -f1)
            name=$(echo "$user_info" | cut -d'|' -f2)
            if [ -n "$email" ]; then
                if [ "$status" = "UNREACHABLE" ] || [ "$status" = "UNKNOWN" ] || [ "$ip" = "(Unspecified)" ]; then
                    subject=$(encode_subject "Tel&eacute;fono N&uacute;mero $extension Desconectado")
                    message='From: '"$SMTP_FROM"'\nTo: '"$email"'\nSubject: '"$subject"'\nContent-Type: text/plain; charset=UTF-8\n\nEstimado/a '"$name"',\n\nHemos detectado que el tel&eacute;fono n&uacute;mero '"$extension"' no est&aacute; conectado a la red. Le recomendamos verificar su conexi&oacute;n para evitar interrupciones en la recepci&oacute;n de llamadas.\n\nAtentamente,\nTu servicio de telefon&iacute;a AJTEL\nContacto: soporte@ajtel.net | Tel: +52 (55) 8526-5050 o *511 desde tu l&iacute;nea'
                    log "Enviando correo a $email: Tel&eacute;fono N&uacute;mero $extension Desconectado"
                    echo -e "$message" | $SENDMAIL -t 2>>"$ERROR_LOG"
                    if [ $? -eq 0 ]; then
                        log "Correo enviado exitosamente a $email"
                    else
                        error_log "Error al enviar correo a $email"
                    fi
                elif [ "$status" = "OK" ]; then
                    subject=$(encode_subject "Tel&eacute;fono N&uacute;mero $extension Reconectado")
                    message='From: '"$SMTP_FROM"'\nTo: '"$email"'\nSubject: '"$subject"'\nContent-Type: text/plain; charset=UTF-8\n\nEstimado/a '"$name"',\n\nNos complace informarle que el tel&eacute;fono n&uacute;mero '"$extension"' se ha reconectado exitosamente a la red. Ahora puede realizar y recibir llamadas con normalidad.\n\nAtentamente,\nTu servicio de telefon&iacute;a AJTEL\nContacto: soporte@ajtel.net | Tel: +52 (55) 8526-5050 o *511 desde tu l&iacute;nea'
                    log "Enviando correo a $email: Tel&eacute;fono N&uacute;mero $extension Reconectado"
                    echo -e "$message" | $SENDMAIL -t 2>>"$ERROR_LOG"
                    if [ $? -eq 0 ]; then
                        log "Correo enviado exitosamente a $email"
                    else
                        error_log "Error al enviar correo a $email"
                    fi
                fi
            fi
        fi

        log "Actualizando estado para extensi&oacute;n $extension"
        grep -v "^$extension " "$STATE_FILE" > /tmp/state_tmp.txt
        echo "$extension $status" >> /tmp/state_tmp.txt
        mv /tmp/state_tmp.txt "$STATE_FILE" 2>>"$ERROR_LOG"
        log "Estado actualizado para extensi&oacute;n $extension"
    done
    log "Ciclo de monitoreo completado, esperando 60 segundos."
    sleep 60
done
EOF
echo "Paso 4 completado: Script principal copiado."

echo "Paso 5: Reemplazando credenciales en el script..."
# Usar un delimitador diferente (#) para evitar problemas con caracteres especiales como / en la contraseña
sed -i "s#MYSQL_USER_VALUE#$MYSQL_USER#" /usr/local/bin/monitor_extension.sh
sed -i "s#MYSQL_PASS_VALUE#$MYSQL_PASS#" /usr/local/bin/monitor_extension.sh
sed -i "s#MYSQL_DB_VALUE#$MYSQL_DB#" /usr/local/bin/monitor_extension.sh
echo "Paso 5 completado: Credenciales reemplazadas."

echo "Paso 6: Configurando permisos y archivo de log..."
chmod +x /usr/local/bin/monitor_extension.sh
touch /var/log/monitor_extension.log
touch /var/log/monitor_extension_error.log
chmod 644 /var/log/monitor_extension.log
chmod 644 /var/log/monitor_extension_error.log
echo "Paso 6 completado: Permisos y archivo de log configurados."

echo "Paso 7: Copiando el archivo de servicio systemd..."
# Copiar el archivo de servicio systemd
cat > /etc/systemd/system/monitor_extension.service << 'EOF'
[Unit]
Description=Monitor FreePBX Extension Status
After=network.target

[Service]
ExecStart=/usr/local/bin/monitor_extension.sh
Restart=always
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
StandardOutput=file:/var/log/monitor_extension.log
StandardError=file:/var/log/monitor_extension_error.log

[Install]
WantedBy=multi-user.target
EOF
echo "Paso 7 completado: Archivo de servicio systemd copiado."

echo "Paso 8: Configurando y activando el servicio..."
chmod 644 /etc/systemd/system/monitor_extension.service
systemctl daemon-reload
systemctl enable monitor_extension.service
systemctl start monitor_extension.service
echo "Paso 8 completado: Servicio configurado y activado."

echo "Instalaci&oacute;n completada exitosamente."

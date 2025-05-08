#!/bin/bash

# ******INSTALADOR DE MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******
# /* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>
#  * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>
# Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante

# Configurar codificación para mostrar acentos correctamente
export LC_ALL=C.UTF-8

# Mostrar el encabezado al iniciar el script
echo "******INSTALADOR DE MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******"
echo "/* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>"
echo " * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>"
echo "Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante"
echo ""
sleep 10

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Verificar si se ejecuta como root
if [ "$(id -u)" != "0" ]; then
    error "Este script debe ejecutarse como root. Usa sudo."
fi

# Extraer credenciales de /etc/freepbx.conf
log "Extrayendo credenciales de la base de datos desde /etc/freepbx.conf..."
if [ -f /etc/freepbx.conf ]; then
    MYSQL_USER=$(grep 'AMPDBUSER' /etc/freepbx.conf | sed -n "s/.*AMPDBUSER.*=.*\"\(.*\)\";.*/\1/p")
    MYSQL_PASS=$(grep 'AMPDBPASS' /etc/freepbx.conf | sed -n "s/.*AMPDBPASS.*=.*\"\(.*\)\";.*/\1/p")
    MYSQL_DB=$(grep 'AMPDBNAME' /etc/freepbx.conf | sed -n "s/.*AMPDBNAME.*=.*\"\(.*\)\";.*/\1/p")
else
    error "No se encontró el archivo /etc/freepbx.conf. Por favor, verifica la instalación de FreePBX."
fi

if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ] || [ -z "$MYSQL_DB" ]; then
    error "No se pudieron extraer las credenciales de la base de datos desde /etc/freepbx.conf."
fi

log "Credenciales extraídas: MYSQL_USER=$MYSQL_USER, MYSQL_DB=$MYSQL_DB"

# Copiar el script principal
log "Copiando el script monitor_extension.sh..."
cat > /usr/local/bin/monitor_extension.sh << 'EOF'
#!/bin/bash

# ******MONITOR DE CONEXION DE EXTENSIONES PARA PBX AJTEL *******
# /* Copyright (C) 1995-2025  AJTEL Comunicaciones    <info@ajtel.net>
#  * Copyright (C) 1995-2025  Andre Vivar Balderrama Bustamante <andrevivar@ajtel.net>
# Desarrollado por AJTEL Comunicaciones y Andre Vivar Balderrama Bustamante

# Archivo para almacenar el estado anterior
STATE_FILE="/tmp/extension_status.txt"

# Conexión a la base de datos de FreePBX
MYSQL_USER="MYSQL_USER_VALUE"
MYSQL_PASS="MYSQL_PASS_VALUE"
MYSQL_DB="MYSQL_DB_VALUE"

# Archivo de log para depuración
LOG_FILE="/var/log/monitor_extension.log"

# Rutas completas a los comandos
ASTERISK="/usr/sbin/asterisk"
MYSQL="/usr/bin/mysql"
SENDMAIL="/usr/sbin/sendmail"

# Función para codificar el Subject en Base64 (para acentos)
encode_subject() {
    subject="$1"
    echo "=?UTF-8?B?$(echo -n "$subject" | base64)?="
}

# Función para registrar mensajes en el log
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Función para obtener el email y nombre de una extensión
get_user_info() {
    extension=$1
    result=$($MYSQL -u$MYSQL_USER -p$MYSQL_PASS -D$MYSQL_DB -N -e "SELECT email, displayname, fname, lname FROM userman_users WHERE default_extension = '$extension'" 2>>"$LOG_FILE")
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
        log "Email encontrado para extension $extension: $email, Nombre: $name"
    else
        log "No se encontro email para extension $extension"
        echo ""
    fi
}

# Obtener configuración de correo desde FreePBX
SMTP_FROM="Tu servicio de telefonía AJTEL <soporte@ajtel.net>"
log "Remitente configurado: $SMTP_FROM"

# Crear archivo de estado si no existe
[ ! -f "$STATE_FILE" ] && touch "$STATE_FILE"

# Crear archivo de log si no existe
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

while true; do
    # Obtener estado actual de las extensiones
    $ASTERISK -rx 'sip show peers' 2>>"$LOG_FILE" | grep -E '^[0-9]+/' | while read -r line; do
        extension=$(echo "$line" | awk '{print $1}' | cut -d'/' -f1)
        ip=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $8}' | grep -E '^(OK|UNREACHABLE|UNKNOWN)$' || echo "$line" | awk '{print $9}' | grep -E '^(OK|UNREACHABLE|UNKNOWN)$' || echo "UNKNOWN")
        prev_status=$(grep "^$extension " "$STATE_FILE" | awk '{print $2}' || echo "UNKNOWN")
        log "Extension $extension: Linea completa='$line'"
        log "Extension $extension: IP=$ip, Estado actual=$status, Estado anterior=$prev_status"

        # Verificar cambios de estado
        if [ "$status" != "$prev_status" ]; then
            user_info=$(get_user_info "$extension")
            email=$(echo "$user_info" | cut -d'|' -f1)
            name=$(echo "$user_info" | cut -d'|' -f2)
            if [ -n "$email" ]; then
                if [ "$status" = "UNREACHABLE" ] || [ "$status" = "UNKNOWN" ] || [ "$ip" = "(Unspecified)" ]; then
                    subject=$(encode_subject "Teléfono Número $extension Desconectado")
                    message='From: '"$SMTP_FROM"'\nTo: '"$email"'\nSubject: '"$subject"'\nContent-Type: text/plain; charset=UTF-8\n\nEstimado/a '"$name"',\n\nHemos detectado que el teléfono número '"$extension"' no está conectado a la red. Le recomendamos verificar su conexión para evitar interrupciones en la recepción de llamadas.\n\nAtentamente,\nTu servicio de telefonía AJTEL\nContacto: soporte@ajtel.net | Tel: +52 (55) 8526-5050 o *511 desde tu línea'
                    echo -e "$message" | $SENDMAIL -t 2>>"$LOG_FILE"
                    if [ $? -eq 0 ]; then
                        log "Correo enviado exitosamente a $email: Teléfono Número $extension Desconectado"
                    else
                        log "Error al enviar correo a $email: Teléfono Número $extension Desconectado"
                    fi
                elif [ "$status" = "OK" ]; then
                    subject=$(encode_subject "Teléfono Número $extension Reconectado")
                    message='From: '"$SMTP_FROM"'\nTo: '"$email"'\nSubject: '"$subject"'\nContent-Type: text/plain; charset=UTF-8\n\nEstimado/a '"$name"',\n\nNos complace informarle que el teléfono número '"$extension"' se ha reconectado exitosamente a la red. Ahora puede realizar y recibir llamadas con normalidad.\n\nAtentamente,\nTu servicio de telefonía AJTEL\nContacto: soporte@ajtel.net | Tel: +52 (55) 8526-5050 o *511 desde tu línea'
                    echo -e "$message" | $SENDMAIL -t 2>>"$LOG_FILE"
                    if [ $? -eq 0 ]; then
                        log "Correo enviado exitosamente a $email: Teléfono Número $extension Reconectado"
                    else
                        log "Error al enviar correo a $email: Teléfono Número $extension Reconectado"
                    fi
                fi
            fi
        fi

        # Actualizar estado
        grep -v "^$extension " "$STATE_FILE" > /tmp/state_tmp.txt
        echo "$extension $status" >> /tmp/state_tmp.txt
        mv /tmp/state_tmp.txt "$STATE_FILE" 2>>"$LOG_FILE"
    done
    log "Ciclo completado, esperando 60 segundos"
    sleep 60
done
EOF

# Sustituir las credenciales en el script generado
sed -i "s/MYSQL_USER_VALUE/$MYSQL_USER/" /usr/local/bin/monitor_extension.sh
sed -i "s/MYSQL_PASS_VALUE/$MYSQL_PASS/" /usr/local/bin/monitor_extension.sh
sed -i "s/MYSQL_DB_VALUE/$MYSQL_DB/" /usr/local/bin/monitor_extension.sh

# Configurar permisos para el script
log "Configurando permisos para monitor_extension.sh..."
chmod +x /usr/local/bin/monitor_extension.sh || error "No se pudo configurar permisos para monitor_extension.sh"

# Crear archivo de log
log "Creando archivo de log..."
touch /var/log/monitor_extension.log || error "No se pudo crear el archivo de log"
chmod 644 /var/log/monitor_extension.log || error "No se pudo configurar permisos para el archivo de log"

# Copiar el archivo de servicio systemd
log "Copiando el archivo de servicio systemd..."
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

# Configurar permisos para el servicio
log "Configurando permisos para el servicio systemd..."
chmod 644 /etc/systemd/system/monitor_extension.service || error "No se pudo configurar permisos para el servicio systemd"

# Recargar systemd y activar el servicio
log "Recargando systemd y activando el servicio..."
systemctl daemon-reload || error "No se pudo recargar systemd"
systemctl enable monitor_extension.service || error "No se pudo habilitar el servicio"
systemctl start monitor_extension.service || error "No se pudo iniciar el servicio"

# Verificar el estado del servicio
log "Verificando el estado del servicio..."
systemctl status monitor_extension.service

log "Instalación completada exitosamente. El servicio monitor_extension está activo."

#!/bin/bash
die() {
	echo "$*"
	exit 1
}

if [[ $EUID -ne 0 ]]; then
	die 'This script must be run as root'
fi

if [ ! -f /etc/wireguard/wg0.conf ]; then
	echo 'Installing WireGuard'
	apt install -y wireguard-tools

	read -ep 'Public Wireguard IP/domain: ' -i "$(curl -s4 ipconfig.io)" PUBIP
	read -ep 'Public Wireguard port: ' -i '51820' PORT

	PRIVKEY="$(wg genkey)"
	PUBKEY="$(echo "$PRIVKEY" | wg pubkey)"

	echo "$PUBKEY" > /etc/wireguard/pubkey
	echo "$PUBIP:$PORT" > /etc/wireguard/endpoint

	echo "[Interface]" > /etc/wireguard/wg0.conf
	echo "Address = 10.66.66.1/24" >> /etc/wireguard/wg0.conf
	echo "ListenPort = $PORT" >> /etc/wireguard/wg0.conf
	echo "PrivateKey = $PRIVKEY" >> /etc/wireguard/wg0.conf

	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/wg.conf
	sysctl --system

	systemctl enable --now wg-quick@wg0
fi

STATUS="$(systemctl status wg-quick@wg0)"
printf 'WireGuard status: %s (%s)\n' \
	`echo "$STATUS" | grep --color=never -Po 'e: \K.*(?= \()'` \
	`echo "$STATUS" | grep --color=never -Po '; \K.*(?=; v)'`

echo 'Clients: '
cat /etc/wireguard/wg0.conf | grep AllowedIPs | cut -c14-

cat << !
a) Add a peer
r) Remove a peer
t) Stop WireGuard interface
s) Start WireGuard interface
e) Enable WireGuard on startup
d) Disable WireGuard on startup
u) Uninstall WireGuard tools
q) Quit script
!

read -p '> ' -n1 OPT
echo
case $OPT in
	a)
		read -p 'Peer name: ' NAME
		read -p 'Peer IP: ' IP

		EXISTS="$(grep -c "# $NAME" /etc/wireguard/wg0.conf)"
		if [[ "$EXISTS" != "0" ]]; then
			die "Peer with that name already exists"
		fi

		EXISTS="$(grep -c "$IP/" /etc/wireguard/wg0.conf)"
		if [[ "$EXISTS" != "0" ]]; then
			die "Peer with that IP already exists"
		fi

		PRIVKEY=$(wg genkey)
		PUBKEY=$(echo "$PRIVKEY" | wg pubkey)
		PSK=$(wg genpsk)
		SERVER_ENDPOINT=$(</etc/wireguard/endpoint)
		SERVER_PUBKEY=$(</etc/wireguard/pubkey)

		echo "#$NAME" >> /etc/wireguard/wg0.conf
		echo "[Peer] #$NAME" >> /etc/wireguard/wg0.conf
		echo "PublicKey = $PUBKEY #$NAME" >> /etc/wireguard/wg0.conf
		echo "PresharedKey = $PSK #$NAME" >> /etc/wireguard/wg0.conf
		echo "AllowedIPs = $IP/32 #$NAME" >> /etc/wireguard/wg0.conf

		wg syncconf wg0 <(wg-quick strip /etc/wireguard/wg0.conf)

		echo "[Interface]" > "wg0-client-$NAME.conf"
		echo "PrivateKey = $PRIVKEY" >> "wg0-client-$NAME.conf"
		echo "Address = $IP/32" >> "wg0-client-$NAME.conf"
		echo "[Peer]" >> "wg0-client-$NAME.conf"
		echo "PublicKey = $SERVER_PUBKEY" >> "wg0-client-$NAME.conf"
		echo "PresharedKey = $PSK" >> "wg0-client-$NAME.conf"
		echo "Endpoint = $SERVER_ENDPOINT" >> "wg0-client-$NAME.conf"
		echo "AllowedIPs = 10.66.66.0/24" >> "wg0-client-$NAME.conf"
		echo "PersistentKeepalive = 25" >> "wg0-client-$NAME.conf"

		cp "wg0-client-$NAME.conf" "wg0-client-$NAME-full.conf"
		sed -i 's/10.66.66.0\/24/0.0.0.0\/0/' "wg0-client-$NAME-full.conf"

		echo "Config written to wg0-client-$NAME.conf"
		echo "Config written to wg0-client-$NAME-full.conf"
		;;
	r)
		grep "^#" /etc/wireguard/wg0.conf | cut -c2- | nl -s ') '

		read -p "Select peer: " NUM

		NAME="$(grep "^#" /etc/wireguard/wg0.conf | cut -c2- | sed -n "$NUM"p)"
		NEW_WG="$(grep -v "#$NAME\$" /etc/wireguard/wg0.conf)"

		echo -e "$NEW_WG" > /etc/wireguard/wg0.conf

		wg syncconf wg0 <(wg-quick strip /etc/wireguard/wg0.conf)
		;;
	t)
		systemctl stop wg-quick@wg0
		;;
	s)
		systemctl start wg-quick@wg0
		;;
	e)
		systemctl enable wg-quick@wg0
		;;
	d)
		systemctl disable wg-quick@wg0
		;;
	u)
		systemctl disable --now wg-quick@wg0
		rm -rf /etc/wireguard
		apt autoremove -y wireguard-tools
		;;
esac

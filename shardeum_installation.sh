#!/usr/bin/env bash
set -e

# Check all things that will be needed for this script to succeed like access to docker and docker-compose
# If any check fails exit with a message on what the user needs to do to fix the problem
command -v git >/dev/null 2>&1 || { echo >&2 "'git' is required but not installed."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo >&2 "'docker' is required but not installed. See https://gitlab.com/shardeum/validator/dashboard/-/tree/dashboard-gui-nextjs#how-to for details."; exit 1; }
if command -v docker-compose &>/dev/null; then
  echo "docker-compose is installed on this machine"
elif docker --help | grep -q "compose"; then
  echo "docker compose subcommand is installed on this machine"
else
  echo "docker-compose or docker compose is not installed on this machine"
  exit 1
fi

export DOCKER_DEFAULT_PLATFORM=linux/amd64

docker-safe() {
  if ! command -v docker &>/dev/null; then
    echo "docker is not installed on this machine"
    exit 1
  fi

  if ! docker $@; then
    echo "Trying again with sudo..."
    sudo docker $@
  fi
}

docker-compose-safe() {
  if command -v docker-compose &>/dev/null; then
    cmd="docker-compose"
  elif docker --help | grep -q "compose"; then
    cmd="docker compose"
  else
    echo "docker-compose or docker compose is not installed on this machine"
    exit 1
  fi

  if ! $cmd $@; then
    echo "Trying again with sudo..."
    sudo $cmd $@
  fi
}

get_ip() {
  local ip
  if command -v ip >/dev/null; then
    ip=$(ip addr show $(ip route | awk '/default/ {print $5}') | awk '/inet/ {print $2}' | cut -d/ -f1 | head -n1)
  elif command -v netstat >/dev/null; then
    # Get the default route interface
    interface=$(netstat -rn | awk '/default/{print $4}' | head -n1)
    # Get the IP address for the default interface
    ip=$(ifconfig "$interface" | awk '/inet /{print $2}')
  else
    echo "Error: neither 'ip' nor 'ifconfig' command found. Submit a bug for your OS."
    return 1
  fi
  echo $ip
}

get_external_ip() {
  external_ip=''
  external_ip=$(curl -s https://api.ipify.org)
  if [[ -z "$external_ip" ]]; then
    external_ip=$(curl -s http://checkip.dyndns.org | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
  fi
  if [[ -z "$external_ip" ]]; then
    external_ip=$(curl -s http://ipecho.net/plain)
  fi
  if [[ -z "$external_ip" ]]; then
    external_ip=$(curl -s https://icanhazip.com/)
  fi
    if [[ -z "$external_ip" ]]; then
    external_ip=$(curl --header  "Host: icanhazip.com" -s 104.18.114.97)
  fi
  if [[ -z "$external_ip" ]]; then
    external_ip=$(get_ip)
    if [ $? -eq 0 ]; then
      echo "The IP address is: $IP"
    else
      external_ip="localhost"
    fi
  fi
  echo $external_ip
}

if [[ $(docker-safe info 2>&1) == *"Cannot connect to the Docker daemon"* ]]; then
    echo "Docker daemon is not running"
    exit 1
else
    echo "Docker daemon is running"
fi

cat << EOF

#########################
# 0. GET INFO FROM USER #
#########################

EOF

RUNDASHBOARD=y

DASHPASS='123321'

echo -e "${fmt}\nSet port for node/Устанавливаем порт для ноды${end}" && sleep 1

wget https://raw.githubusercontent.com/fackNode/shardeum/main/ports_cheker.sh && chmod +x ports_cheker.sh && ./ports_cheker.sh
source ports_cheker.sh
DASHPORT=$USEPORT

echo -e "${fmt}\nNode port/Порт ноды - $DASHPORT${end}" && sleep 1

echo "Your dashboard link - https://$(wget -qO- eth0.me):$DASHPORT" >> shardeum_dashboard_link.txt

# while :; do
#   echo "To run a validator on the Sphinx network, you will need to open two ports in your firewall."
#   read -p "This allows p2p commnication between nodes. Enter the first port (1025-65536) for p2p comminucation (default 9001): " SHMEXT
#   SHMEXT=${SHMEXT:-9001}
#   [[ $SHMEXT =~ ^[0-9]+$ ]] || { echo "Enter a valid port"; continue; }
#   if ((SHMEXT >= 1025 && SHMEXT <= 65536)); then
#     SHMEXT=${SHMEXT:-9001}
#   else
#     echo "Port out of range, try again"
#   fi
#   read -p "Enter the second port (1025-65536) for p2p comminucation (default 10001): " SHMINT
#   SHMINT=${SHMINT:-10001}
#   [[ $SHMINT =~ ^[0-9]+$ ]] || { echo "Enter a valid port"; continue; }
#   if ((SHMINT >= 1025 && SHMINT <= 65536)); then
#     SHMINT=${SHMINT:-10001}
#     break
#   else
#     echo "Port out of range, try again"
#   fi
# done
wget https://raw.githubusercontent.com/fackNode/shardeum/main/HMEXT_SHMINT_ports_checker.sh && chmod +x HMEXT_SHMINT_ports_checker.sh && ./HMEXT_SHMINT_ports_checker.sh
source HMEXT_SHMINT_ports_checker.sh
SHMEXT=$HMX
SHMINT=$SHN

cat <<EOF

SHMEXT port - $SHMEXT
SHMINT port - $SHMINT

EOF
sleep 1

NODEHOME=/home/user/.shardeum

# PS3='Select a network to connect to: '
# options=("betanet")
# select opt in "${options[@]}"
# do
#     case $opt in
#         "betanet")
#             APPSEEDLIST="18.192.49.22"
#             APPMONITOR="3.76.28.10"
#             break
#             ;;
#         *) echo "invalid option $REPLY";;
#     esac
# done

APPSEEDLIST="archiver-sphinx.shardeum.org"
APPMONITOR="monitor-sphinx.shardeum.org"

cat <<EOF

###########################
# 1. Pull Compose Project #
###########################

EOF

if [ -d "$NODEHOME" ]; then
  if [ "$NODEHOME" != "$(pwd)" ]; then
    echo "Removing existing directory $NODEHOME..."
    rm -rf "$NODEHOME"
  else
    echo "Cannot delete current working directory. Please move to another directory and try again."
  fi
fi

git clone https://gitlab.com/shardeum/validator/dashboard.git ${NODEHOME} &&
  cd ${NODEHOME} &&
  chmod a+x ./*.sh

cat <<EOF

###############################
# 2. Create and Set .env File #
###############################

EOF

SERVERIP=$(get_external_ip)
LOCALLANIP=$(get_ip)
cd ${NODEHOME} &&
touch ./.env
cat >./.env <<EOL
APP_IP=auto
APP_SEEDLIST=${APPSEEDLIST}
APP_MONITOR=${APPMONITOR}
DASHPASS=${DASHPASS}
DASHPORT=${DASHPORT}
SERVERIP=${SERVERIP}
LOCALLANIP=${LOCALLANIP}
SHMEXT=${SHMEXT}
SHMINT=${SHMINT}
EOL

cat <<EOF

##########################
# 3. Clearing Old Images #
##########################

EOF

./cleanup.sh

cat <<EOF

##########################
# 4. Building base image #
##########################

EOF

cd ${NODEHOME} &&
docker-safe build --no-cache -t test-dashboard -f Dockerfile --build-arg RUNDASHBOARD=${RUNDASHBOARD} .

cat <<EOF

############################
# 5. Start Compose Project #
############################

EOF

cd ${NODEHOME}
if [[ "$(uname)" == "Darwin" ]]; then
  sed "s/- '8080:8080'/- '$DASHPORT:$DASHPORT'/" docker-compose.tmpl > docker-compose.yml
  sed -i '' "s/- '9001-9010:9001-9010'/- '$SHMEXT:$SHMEXT'/" docker-compose.yml
  sed -i '' "s/- '10001-10010:10001-10010'/- '$SHMINT:$SHMINT'/" docker-compose.yml
else
  sed "s/- '8080:8080'/- '$DASHPORT:$DASHPORT'/" docker-compose.tmpl > docker-compose.yml
  sed -i "s/- '9001-9010:9001-9010'/- '$SHMEXT:$SHMEXT'/" docker-compose.yml
  sed -i "s/- '10001-10010:10001-10010'/- '$SHMINT:$SHMINT'/" docker-compose.yml
fi
./docker-up.sh

echo "Starting image. This could take a while..."
(docker-safe logs -f shardeum-dashboard &) | grep -q 'done'

#Do not indent
if [ $RUNDASHBOARD = "y" ]
then
cat <<EOF
  To use the Web Dashboard:
    1. Open a web browser and navigate to the web dashboard at "https://$(wget -qO- eth0.me):$DASHPORT"
    2. Go to the Settings tab and connect a wallet.
    3. Go to the Maintenance tab and click the Start Node button.

  If this validator is on the cloud and you need to reach the dashboard over the internet,
  please set a strong password and use the external IP instead of localhost.
EOF
fi

cat <<EOF

To use the Command Line Interface:
	1. Navigate to the Shardeum home directory ($NODEHOME).
	2. Enter the validator container with ./shell.sh.
	3. Run "operator-cli --help" for commands

EOF

if docker ps -a | grep -q 'local-dashboard'; then
  echo -e "${fmt}\nNode installed correctly / Нода установлена корректно${end}" && sleep 1
  cat /home/user/shardeum_dashboard_link.txt
else
  echo -e "${err}\nNode installed incorrectly / Нода установлена некорректно${end}" && sleep 1
fi

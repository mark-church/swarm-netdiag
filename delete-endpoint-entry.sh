#!/bin/bash
set -e
cmd=${1:-""}

# - get docker swarm join-token
# - recieve starting values (join token, network name, bad IP address)
# - spin up netdiag container on bare metal host
# - kill -HUP $(pidof dockerd)
# - docker swarm join --token
# - validate with "curl localhost:2000/help"
# - validate that entry exists
# - remove entry from sd table
# - remove entry from overlay table

function init() {
    echo "Creating swarm-netdiag container ... "
    docker run --name swarm-netdiag --rm -itd --privileged --network host \
    	--env "RougeIP=$rogueIP" \
    	--env "NetworkName=$(NETWORK_NAME)" \
    	--env "JoinToken=$(joinToken)" \
    	--env "JoinIPPort=$(joinIPport)" \
    	chrch/swarm-netdiag
    echo "swarm-netdiag container created."

	docker exec -it swarm-netdiag sh -c 'echo $(JoinIPPort)'

	echo "Joining the Swarm cluster ..."
	docker exec -it swarm-netdiag sh -c 'kill -HUP $(pidof dockerd)'

	docker exec -it swarm-netdiag sh -c "docker swarm join --token $JoinToken $JoinIPPort"

	docker exec -it swarm-netdiag sh -c "docker swarm join --token $JoinToken $JoinIPPort"
}





if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]; then

    rougeIP=$1
    NETWORK_NAME=$2
    joinToken=$3
    joinIPport=$4

    echo "Starting ip-remove.sh ..."
    init
    echo "Initialization complete."
    echo ""


else
    echo "Incorrect usage"
    echo ""
    echo "Usage:    ./ip-remove.sh <IP-address> <network-name> <swarm-join-token> <swarm-join-IP:port>"
    echo ""
fi
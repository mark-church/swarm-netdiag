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
    	--env "NetworkID=$networkID" \
    	--env "JoinToken=$joinToken" \
    	--env "JoinIPPort=$joinIPport" \
    	chrch/swarm-netdiag:centos

    docker inspect swarm-netdiag

    echo "swarm-netdiag container created."
    docker logs -t swarm-netdiag

	echo "SIGHUP to dockerd ..."
	docker exec -it swarm-netdiag sh -c 'kill -HUP $(ps aux | grep dockerd | grep -v grep | awk -n '\''{print $2}'\'')'

	echo "Joining the Swarm cluster ..."
	docker exec -it swarm-netdiag sh -c 'docker swarm join --token $JoinToken $JoinIPPort'

	#if [ $(docker exec -it swarm-netdiag sh -c 'curl -s localhost:2000/help | grep "getentry"') ]; then
	#	echo "found"
	#else
	#	echo "not found"
	#fi

	#docker exec -it swarm-netdiag sh -c 'NetworkID=$(docker network ls --no-trunc | grep -i "$NetworkName" | awk '\''{print $1}'\'')'

	docker exec -it swarm-netdiag sh -c 'curl localhost:2000/joinnetwork?nid=$NetworkID'
	docker logs -t swarm-netdiag

}





if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]; then

    rogueIP=$1
    networkID=$2
    joinToken=$3
    joinIPport=$4

    echo "Starting ip-remove.sh ..."
    init
    echo "Initialization complete."
    echo ""


else
    echo "Incorrect usage"
    echo ""
    echo "Usage:    ./ip-remove.sh <IP-address> <network-id> <swarm-join-token> <swarm-join-IP:port>"
    echo ""
fi

# Swarm NetDiag Instructions


## How to use this stuff

- `validate.sh` is a custom script that will validate whether the Swarm VIP pool is consistent with the IPs that the valid tasks should have
- `ip-remove.sh` is a custom script that will remove an IP address entry from the Swarm network database.
- The instructions below show how to build the NetDiag container locally and then use it to inspect the Swarm network database


## Building Swarm NetDiag

Building NetDiag requires a few files and scripts to run that are listed in the directory below.

```
root@docker:/home/ubuntu/bin# ls
daemon.json  diagnosticClient  Dockerfile  wrapdocker


root@docker:/home/ubuntu/bin# cat Dockerfile
FROM centos:7
RUN yum update -y && yum install -y \
    curl \
    ca-certificates \
    yum-utils \
    epel-release
RUN yum install -y jq
RUN rpm --import https://download.docker.com/linux/centos/gpg
RUN yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo"
RUN yum update -y && yum install --enablerepo=docker-ce-test -y \
    docker-ce
RUN mkdir /tool
WORKDIR /tool
COPY daemon.json /etc/docker/daemon.json
COPY diagnosticClient /tool/diagnosticClient
COPY wrapdocker /usr/local/bin/wrapdocker
RUN chmod +x /usr/local/bin/wrapdocker
CMD ["/usr/local/bin/wrapdocker"]

root@docker:/home/ubuntu/bin# docker build -t swarm-netdiag .
Sending build context to Docker daemon  19.31MB
Step 1/13 : FROM centos:7
 ---> 3fa822599e10

...
...
...

Step 13/13 : CMD /usr/local/bin/wrapdocker
 ---> Using cache
 ---> 2254ace400a6
Successfully built 2254ace400a6
Successfully tagged swarm-netdiag:lates
```


## Initializing NetDiag


Starting the swarm-netdiag container. Then verify that the Docker engine has started inside the container by looking at the contianer logs for `swarm-netdiag`.

```
root@docker:/home/ubuntu/bin# docker run --name swarm-netdiag --rm -itd --privileged --network host swarm-netdiag
e3c77bb9e938952760d63a2431f1ad71c2955b81d63d24537d3d5726e755fd32

root@docker:/home/ubuntu/bin# docker logs swarm-netdiag | head -n5
ln: failed to create symbolic link '/sys/fs/cgroup/systemd/name=systemd': Operation not permitted
DEBU[2017-12-15T22:55:16.514983582Z] Listener created for HTTP on unix (/var/run/docker.sock)
INFO[2017-12-15T22:55:16.515676769Z] libcontainerd: started new docker-containerd process  pid=60
INFO[0000] starting containerd                           module=containerd revision=89623f28b87a6004d4b785663257362d1658a729 version=v1.0.0
INFO[0000] setting subreaper...                          module=containerd
```

Go in to the container and send a reset signal to the Docker process (pid 1). Congratulations, you are now running Docker inside Docker!

```
root@docker:/home/ubuntu/bin# docker exec -it swarm-netdiag sh

sh-4.2#
sh-4.2# docker -v
Docker version 17.12.0-ce-rc3, build 80c8033
sh-4.2# kill -HUP $(pidof dockerd)
```

Now join the Swarm cluster you are trying to troubleshoot with this node. Use the join-token from your Swarm cluster to do the join.

On your Swarm node ...

```
root@swarm-controller:/# docker swarm join-token worker
To add a worker to this swarm, run the following command:

docker swarm join --token SWMTKN-1-0vivsd0q7fpyvxadwjjiwrm5xv41vtk1gdcatkf9oe527f5pwc-bos53jkrdpb9szj84zuag0trl 172.31.18.83:2377
```

Back inside your `swarm-netdiag` container ...

```
sh-4.2# docker swarm join --token SWMTKN-1-0vivsd0q7fpyvxadwjjiwrm5xv41vtk1gdcatkf9oe527f5pwc-bos53jkrdpb9szj84zuag0trl 172.31.18.83:2377
This node joined a swarm as a worker.
```

## Using Swarm NetDiag 
The NetDiag tool exposes port 2000 locally inside the contianer which will expose the data structures of the NetworkDB.


`/ready` will indicate to us whether the tool is working or not.

```
sh-4.2# curl localhost:2000/ready
OK
```


`/help` will give us the full list of commands possible with this tool.

```
sh-4.2# curl localhost:2000/help
OK
/getentry
/join
/
/ready
/leavenetwork
/deleteentry
/help
/stackdump
/createentry
/updateentry
/gettable
/networkpeers
/clusterpeers
/joinnetwork
```

> `/createentry` and `/updateentry` are experimental and **should not** be used unless with assistance from Docker!


Next we are going to inspect the data structures of the Docker NetworkDB. First we will pick an overlay network to do our inspection on.

```
sh-4.2# docker network ls --no-trunc
NETWORK ID                                                         NAME                DRIVER              SCOPE
ff6a3e2aea4087aa24018a5efce56810d7b3abf0399e8f433f89be6c3a0ce422   bridge              bridge              local
e36bf1115f7af255df82f069c401e06e845ca72b00a8df5033023e637e257bf8   docker_gwbridge     bridge              local
6ca5b18809dc0195be7b17d82bae9b3b0b155fedae58b5f408b94466fc4335d8   host                host                local
d3fc44b95fc1dfd840c5a44d8e4bc1878f18825440718e26549aea3ec76b9304   none                null                local
qso79uv6do7mty9luolkosjit                                          ovl1                overlay             swarm
```

We take the full Network ID of the network we want to inspect and then we can see what the peers are that are participating in this network.

```
sh-4.2# curl localhost:2000/networkpeers?nid=qso79uv6do7mty9luolkosjit
OK
total entries: 3
0) ip-172-31-26-196-6add29784d11 -> 172.31.26.196
1) ip-172-31-19-163-2cccaab1f688 -> 172.31.19.163
2) 4c26c14fffcd -> 172.31.28.169
```

#### Removing a Table Entry

Note that to use most of the endpoints supported by NetDiag we have to join the overlay network from our NetDiag container. Here is the general flow for removing a table entry:

1. Run the diagnosticClient to identify the table entry keys
2. Use `/joinnetwork` to join the overlay network
2. Use `/deleteentry` to remove the entry


```
sh-4.2# curl localhost:2000/joinnetwork?nid=qso79uv6do7mty9luolkosjit
OK
```

By utiliziing the `DiagnosticClient` script mentioned below we can dump the contents of a table to see all the entries. We use the keys from this table to get and delete the entries. As an example, we will remove the following entry from the Service Discovery table. This will take it out of the VIP LB and also out of DNS resolution. It will remove task the `blueserve.2.y6qf88yzrczyk5yh680m0br0n` IP (`10.0.0.32`) from the table.

```
# From the SD table ...
DEBU[0000] key:a09dfdc3caf0cc218d1a756d8384d169ca1ae3b9dd0de34823354059c55ca6d2 value:{Name:blueserve.2.y6qf88yzrczyk5yh680m0br0n 
ServiceName:blueserve ServiceID:rm34snq4jsmdiz4to5zyxi6d9 
VirtualIP:10.0.0.2 EndpointIP:10.0.0.32 
IngressPorts:[] Aliases:[] TaskAliases:[78e59beb26bf]} owner:ip-172-31-19-163-2cccaab1f688

sh-4.2# curl "localhost:2000/deleteentry?tname=endpoint_table&nid=qso79uv6do7mty9luolkosjit&key=a09dfdc3caf0cc218d1a756d8384d169
ca1ae3b9dd0de34823354059c55ca6d2"
OK
```

This entry is now deleted from the SD table. The same process can be done for the overlay table. The names for these tables are `endpoint_table` and `overlay_peer_table` respectively.



## Using the DiagnosticClient Script with NetDiag


The `diagnosticClient` script will use `Swarm-NetDiag` to do a complete dump of the data structures. It can inspect the `overlay` table to understand overlay endpoints and the `sd` table to understand service discovery mappings

#### Service Discovery Table

```
sh-4.2# ./diagnosticClient -net qso79uv6do7mty9luolkosjit -t sd -v
INFO[0000] Connecting to 127.0.0.1:2000 checking ready
INFO[0000] Fetch peers
DEBU[0000] Parsing JSON response
DEBU[0000] name:8c55734213dd ip:172.31.17.223
DEBU[0000] name:ip-172-31-24-72-cd4cef9a2303 ip:172.31.24.72
DEBU[0000] name:ip-172-31-18-83-b0e6579643a6 ip:172.31.18.83
INFO[0000] Joining the network:ymtiuiwb9vw6v96ms78bqcdv0
INFO[0000] Fetch peers ymtiuiwb9vw6v96ms78bqcdv0
DEBU[0000] Parsing JSON response
DEBU[0000] name:ip-172-31-18-83-b0e6579643a6 ip:172.31.18.83
DEBU[0000] name:ip-172-31-24-72-cd4cef9a2303 ip:172.31.24.72
DEBU[0000] name:8c55734213dd ip:172.31.17.223
INFO[0000] Fetch endpoint_table table and check owners
DEBU[0000] Parsing data structures
DEBU[0000] key:8146895ad4a91283c4c821b0e43901e613b50f2db01746f9a06fe55a9c955608 value:{Name:testserv.2.o77j2ihahjcpw1sg1usfv4z3f ServiceName:testserv ServiceID:4dmh38dyfi78js3xgrqi6i9bk VirtualIP:10.0.0.2 EndpointIP:10.0.0.9 IngressPorts:[] Aliases:[] TaskAliases:[09f29fba4ccf]} owner:ip-172-31-18-83-b0e6579643a6
DEBU[0000] key:8e8adc8b34fe2862e1d018ba6a8f53919202c31a74d2e4f87f2565e388289ae5 value:{Name:nostalgic_jennings.u5u7ixc879r7ypitqamv74r4m.ouyk4zc4t85mh4qbzikc0zs33 ServiceName:nostalgic_jennings ServiceID:d6fmygxmze86g7qpbnlxnoaxc VirtualIP:10.0.0.10 EndpointIP:10.0.0.13 IngressPorts:[] Aliases:[] TaskAliases:[52fd395ff867]} owner:ip-172-31-24-72-cd4cef9a2303
DEBU[0000] key:a45f6587fc5479793ea5861b4bee02094c84ff611707b60bf1589f608933dbcc value:{Name:nostalgic_jennings.qhkcdr3onigb8gh02hyfeuyx3.0uodvvmukvllvd2fcxncd8nqk ServiceName:nostalgic_jennings ServiceID:d6fmygxmze86g7qpbnlxnoaxc VirtualIP:10.0.0.10 EndpointIP:10.0.0.12 IngressPorts:[] Aliases:[] TaskAliases:[cf24c3ebc236]} owner:ip-172-31-18-83-b0e6579643a6
DEBU[0000] key:d9711b7c5d081a3543c22c154295b461a97dc215b4ff283c88735e8efb6e5194 value:{Name:testserv.1.v17zx7kz884mh075tt5j19ltl ServiceName:testserv ServiceID:4dmh38dyfi78js3xgrqi6i9bk VirtualIP:10.0.0.2 EndpointIP:10.0.0.14 IngressPorts:[] Aliases:[] TaskAliases:[115f44e33465]} owner:ip-172-31-18-83-b0e6579643a6
DEBU[0000] key:f342b5983a0bdb8bad3e236b4530abfe5837fc794de9a7b5394b2b0912f849d4 value:{Name:testserv.3.iu83i3x8r5hzmq9cwbxy1mpbm ServiceName:testserv ServiceID:4dmh38dyfi78js3xgrqi6i9bk VirtualIP:10.0.0.2 EndpointIP:10.0.0.8 IngressPorts:[] Aliases:[] TaskAliases:[8688a0323d7b]} owner:ip-172-31-24-72-cd4cef9a2303
```

#### Overlay Table
```
sh-4.2# ./diagnosticClient -net ymtiuiwb9vw6v96ms78bqcdv0 -t overlay -v
INFO[0000] Connecting to 127.0.0.1:2000 checking ready
INFO[0000] Fetch peers
DEBU[0000] Parsing JSON response
DEBU[0000] name:ip-172-31-24-72-cd4cef9a2303 ip:172.31.24.72
DEBU[0000] name:ip-172-31-18-83-b0e6579643a6 ip:172.31.18.83
DEBU[0000] name:8c55734213dd ip:172.31.17.223
INFO[0000] Joining the network:ymtiuiwb9vw6v96ms78bqcdv0
INFO[0000] Fetch peers ymtiuiwb9vw6v96ms78bqcdv0
DEBU[0000] Parsing JSON response
DEBU[0000] name:ip-172-31-18-83-b0e6579643a6 ip:172.31.18.83
DEBU[0000] name:ip-172-31-24-72-cd4cef9a2303 ip:172.31.24.72
DEBU[0000] name:8c55734213dd ip:172.31.17.223
INFO[0000] Fetch overlay_peer_table table and check owners
DEBU[0000] Parsing data structures
DEBU[0000] key:a45f6587fc5479793ea5861b4bee02094c84ff611707b60bf1589f608933dbcc value:{EndpointIP:10.0.0.12/24 EndpointMAC:02:42:0a:00:00:0c TunnelEndpointIP:172.31.18.83} owner:ip-172-31-18-83-b0e6579643a6
DEBU[0000] key:d9711b7c5d081a3543c22c154295b461a97dc215b4ff283c88735e8efb6e5194 value:{EndpointIP:10.0.0.14/24 EndpointMAC:02:42:0a:00:00:0e TunnelEndpointIP:172.31.18.83} owner:ip-172-31-18-83-b0e6579643a6
DEBU[0000] key:f342b5983a0bdb8bad3e236b4530abfe5837fc794de9a7b5394b2b0912f849d4 value:{EndpointIP:10.0.0.8/24 EndpointMAC:02:42:0a:00:00:08 TunnelEndpointIP:172.31.24.72} owner:ip-172-31-24-72-cd4cef9a2303
DEBU[0000] key:8146895ad4a91283c4c821b0e43901e613b50f2db01746f9a06fe55a9c955608 value:{EndpointIP:10.0.0.9/24 EndpointMAC:02:42:0a:00:00:09 TunnelEndpointIP:172.31.18.83} owner:ip-172-31-18-83-b0e6579643a6
DEBU[0000] key:8e8adc8b34fe2862e1d018ba6a8f53919202c31a74d2e4f87f2565e388289ae5 value:{EndpointIP:10.0.0.13/24 EndpointMAC:02:42:0a:00:00:0d TunnelEndpointIP:172.31.24.72} owner:ip-172-31-24-72-cd4cef9a2303
```



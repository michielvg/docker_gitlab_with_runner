# Gitlab with ci/cd runner
(and automated ssl cert setup)

# Quickstart
* Dependencies
    * Docker
    * jq
* Create external volumes
```bash
$ docker volume create gitlab-home
gitlab-home
$ # Create recursive folders
$ docker run -it --rm -v gitlab-home:/data debian:stable-slim mkdir /data/config /data/log /data/data

$ docker volume create gitlab-runner-config
gitlab-runner-config
$ # Create recursive folders
$ docker run -it --rm -v gitlab-runner-config:/data debian:stable-slim mkdir /data/runner-0
```
* Configure your hostname
```bash
$ echo "HOSTNAME=gitlab.example.com" > .env 
```
* Start the containers
```bash
$ docker compose up -d
```

* Add container ip to hosts file for easy access
```bash
$ . .env
$ ip=$(docker network inspect ${HOSTNAME//./}_default | jq -r ".[0].Containers | to_entries[] | first(.value).IPv4Address" | cut -f1 -d"/")
$ echo $ip $HOSTNAME | sudo tee -a /etc/hosts
```

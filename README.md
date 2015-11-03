# Single node Cloudera env


## Used software

- Cloudera Manager

## Info

This configuration builds docker for Cloudera Manager with services autoconfiguration after first boot

## How to build

generate Dockerfile with appropriate jdk and cdh version

```
./make_dockerfile.sh profiles/jdk1.8_cdh5.3.3
```

or

```
./make_dockerfile.sh profiles/jdk1.8_cdh5.4.8
```

etc...

run image building

```
docker-compose build
```

You can create your own profile with needed jdk and cdh version, put it in profile directory and run make_dockerfile.sh script.

## How to run

run in background

```
docker-compose up -d
```

check status

```
docker-compose logs
```

## How to connect

Look into the docker-compose.yml for exposed ports
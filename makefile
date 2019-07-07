# {{{ -- meta

HOSTARCH  := $(shell uname -m | sed "s_armv6l_armhf_")# x86_64# on travis.ci
ARCH      := $(shell uname -m | sed "s_armv6l_armhf_")# armhf/x86_64 auto-detect on build and run
OPSYS     := alpine
SHCOMMAND := /bin/bash
SVCNAME   := rsyslog
USERNAME  := woahbase

CMD       := sleep 5; rsyslogd -v; logrotate --version;# used for testing or overridden when running

PUID      := $(shell id -u)
PGID      := $(shell id -g)# gid 100(users) usually pre exists

DOCKERSRC := $(OPSYS)-glibc#
DOCKEREPO := $(OPSYS)-$(SVCNAME)
IMAGETAG  := $(USERNAME)/$(DOCKEREPO):$(ARCH)

CNTNAME   := $(SVCNAME) # name for container name : docker_name, hostname : name

BUILD_NUMBER    := 0#assigned in .travis.yml
BRANCH          := master

# local paths
DIR_CONF        := $(CURDIR)/data/config
DIR_LOG         := $(CURDIR)/data/log
DIR_SPOOL       := $(CURDIR)data//spool

# paths inside container
RSYSLOG_CONF    := /config/rsyslog.conf
LOGROTATE_CONF  := /config/logrotate.conf
LOGROTATE_STATE := /config/logrotate.state
SYS_HOSTNAME    := localhost# $(shell cat /etc/hostname).local
FWD_TO_HOST     := localhost#
FWD_TO_PORT     := 2514
FWD_PROTOCOL    := relp

# -- }}}

# {{{ -- flags

BUILDFLAGS := --rm --force-rm --compress \
	-f $(CURDIR)/Dockerfile_$(ARCH) \
	-t $(IMAGETAG) \
	--build-arg DOCKERSRC=$(USERNAME)/$(DOCKERSRC):$(ARCH) \
	--build-arg PUID=$(PUID) \
	--build-arg PGID=$(PGID) \
	--build-arg http_proxy=$(http_proxy) \
	--build-arg https_proxy=$(https_proxy) \
	--build-arg no_proxy=$(no_proxy)  \
	--label online.woahbase.source-image=$(DOCKERSRC) \
	--label online.woahbase.build-number=$(BUILD_NUMBER) \
	--label online.woahbase.branch=$(BRANCH) \
	--label org.label-schema.build-date=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
	--label org.label-schema.name=$(DOCKEREPO) \
	--label org.label-schema.schema-version="1.0" \
	--label org.label-schema.url="https://woahbase.online/" \
	--label org.label-schema.usage="https://woahbase.online/\#/images/$(DOCKEREPO)" \
	--label org.label-schema.vcs-ref=$(shell git rev-parse --short HEAD) \
	--label org.label-schema.vcs-url="https://github.com/$(USERNAME)/$(DOCKEREPO)" \
	--label org.label-schema.vendor=$(USERNAME)

CACHEFLAGS := --no-cache=true --pull
MOUNTFLAGS := \
	-v $(DIR_CONF):/config \
	-v $(DIR_LOG):/var/log \
	-v $(DIR_SPOOL):/var/spool/rsyslog \
	-v /run/systemd/journal:/run/systemd/journal \
	# --workdir /home/alpine

NAMEFLAGS  := --name docker_$(CNTNAME) \
	--hostname $(SYS_HOSTNAME) \
	#needed so container logs end up in same dir as the docker host device when forwarding.

OTHERFLAGS := -v /etc/hosts:/etc/hosts:ro -v /etc/localtime:/etc/localtime:ro -e TZ=Asia/Kolkata
PORTFLAGS  := -p 2514:2514 -p 514:514/tcp -p 514:514/udp

RUNFLAGS   := -c 256 -m 256m \
	-e PGID=$(PGID) -e PUID=$(PUID) \
	-e RSYSLOG_CONF=$(RSYSLOG_CONF) \
	-e LOGROTATE_CONF=$(LOGROTATE_CONF) \
	-e LOGROTATE_STATE=$(LOGROTATE_STATE) \
	-e SYS_HOSTNAME=$(SYS_HOSTNAME) \
	-e FWD_TO_HOST=$(FWD_TO_HOST) \
	-e FWD_TO_PORT=$(FWD_TO_PORT) \
	-e FWD_PROTOCOL=$(FWD_PROTOCOL) \
	# -u alpine

# -- }}}

# {{{ -- docker targets

all : run

build :
	echo "Building for $(ARCH) from $(HOSTARCH)";
	if [ "$(ARCH)" != "$(HOSTARCH)" ]; then make regbinfmt ; fi;
	docker build $(BUILDFLAGS) $(CACHEFLAGS) .

clean :
	docker images | awk '(NR>1) && ($$2!~/none/) {print $$1":"$$2}' | grep "$(USERNAME)/$(DOCKEREPO)" | xargs -n1 docker rmi

logs :
	docker logs -f docker_$(CNTNAME)

pull :
	docker pull $(IMAGETAG)

push :
	docker push $(IMAGETAG);
	if [ "$(ARCH)" = "$(HOSTARCH)" ]; \
		then \
		LATESTTAG=$$(echo $(IMAGETAG) | sed 's/:$(ARCH)/:latest/'); \
		docker tag $(IMAGETAG) $${LATESTTAG}; \
		docker push $${LATESTTAG}; \
	fi;

restart :
	docker ps -a | grep 'docker_$(CNTNAME)' -q && docker restart docker_$(CNTNAME) || echo "Service not running.";

rm :
	docker rm -f docker_$(CNTNAME)

run :
	docker run --rm -it $(NAMEFLAGS) $(RUNFLAGS) $(PORTFLAGS) $(MOUNTFLAGS) $(OTHERFLAGS) $(IMAGETAG)

shell :
	docker run --rm -it $(NAMEFLAGS) $(RUNFLAGS) $(PORTFLAGS) $(MOUNTFLAGS) $(OTHERFLAGS) --entrypoint $(SHCOMMAND) $(IMAGETAG)

rdebug :
	docker exec -u root -it docker_$(CNTNAME) $(SHCOMMAND)

debug :
	docker exec -u $(PUID) -it docker_$(CNTNAME) $(SHCOMMAND)

stop :
	docker stop -t 2 docker_$(CNTNAME)

test :
	docker run --rm -it $(NAMEFLAGS) $(RUNFLAGS) --entrypoint $(SHCOMMAND) $(IMAGETAG) -ec "$(CMD)"

# -- }}}

# {{{ -- other targets

regbinfmt :
	docker run --rm --privileged multiarch/qemu-user-static:register --reset

logclean :
	rm -rf data/log/*/*/*.log

# -- }}}

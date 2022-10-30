FROM arm64v8/debian:9

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get -y --no-install-recommends install \
        curl \
        wget \
        mount \
        psmisc \
        dpkg \
        apt \
        lsb-release \
        sudo \
        gnupg \
        apt-transport-https \
        ca-certificates \
        dirmngr \
        mdadm \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get -y --no-install-recommends install systemd \
    && find /etc/systemd/system \
        /lib/systemd/system \
        -path '*.wants/*' \
        -not -name '*journald*' \
        -not -name '*systemd-tmpfiles*' \
        -not -name '*systemd-user-sessions*' \
        -exec rm \{} \; \
    && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGKILL

RUN apt-get update \
    && apt-get -y --no-install-recommends install postgresql \
    && sed -i 's/peer/trust/g' /etc/postgresql/9.6/main/pg_hba.conf \
    && rm -rf /var/lib/apt/lists/*

COPY put-deb-files-here/*.deb files/postgresql.sh /
COPY put-version-file-here/version /usr/lib/version

RUN apt-get -y --no-install-recommends install /ubnt-archive-keyring_*_arm64.deb \
    && echo 'deb https://apt.artifacts.ui.com stretch main release beta' > /etc/apt/sources.list.d/ubiquiti.list \
    && chmod 666 /etc/apt/sources.list.d/ubiquiti.list \
    && apt-get update \
    && apt-get -y --no-install-recommends install /*.deb unifi-protect \
    && rm -f /*.deb \
    && rm -rf /var/lib/apt/lists/* \
    && /postgresql.sh \
    && rm /postgresql.sh \
    && echo "exit 0" > /usr/sbin/policy-rc.d \
    && sed -i 's/redirectHostname: unifi//' /usr/share/unifi-core/app/config/config.yaml \
    && mv /sbin/mdadm /sbin/mdadm.orig \
    && mv /usr/sbin/smartctl /usr/sbin/smartctl.orig

COPY files/sbin /sbin/
COPY files/usr /usr/

VOLUME ["/srv", "/data", "/persistent"]

CMD ["/lib/systemd/systemd"]

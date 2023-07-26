
FROM debian AS firmware
RUN apt-get update \
    && apt-get -y install \
        wget jq binwalk dpkg-repack dpkg ca-certificates
WORKDIR /opt
RUN wget -q --output-document - "https://fw-update.ubnt.com/api/firmware?filter=eq~~platform~~unvr&filter=eq~~channel~~release&sort=-version&limit=10" | \
        jq -r '._embedded.firmware | map(select(.probability_computed == 1))[0] | ._links.data.href' \
        wget -qO fwupdate.bin -i -
RUN binwalk --run-as=root -e fwupdate.bin
RUN dpkg-query --admindir=_fwupdate.bin.extracted/squashfs-root/var/lib/dpkg/ -W -f="\${package} | \${Maintainer}\n" | \
        grep -E "@ubnt.com|@ui.com" | cut -d "|" -f 1 > packages.txt
RUN mkdir -p debs
WORKDIR /opt/debs
RUN while read pkg; do \
        dpkg-repack --root=../_fwupdate.bin.extracted/squashfs-root/ --arch=arm64 ${pkg}; \
    done < ../packages.txt

FROM arm64v8/debian:11
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
        iproute2 \
        ethtool \
        procps \
        systemd-timesyncd \
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

RUN curl -sL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" > /etc/apt/sources.list.d/postgresql.list \
    && apt-get update \
    && apt-get -y --no-install-recommends install postgresql-client-14 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=firmware /opt/_fwupdate.bin.extracted/squashfs-root/usr/lib/version /usr/lib/version

RUN --mount=type=bind,from=firmware,source=/opt/debs,target=/debs apt-get -y --no-install-recommends install /debs/ubnt-archive-keyring_*_arm64.deb
RUN echo 'deb https://apt.artifacts.ui.com bullseye main release beta' > /etc/apt/sources.list.d/ubiquiti.list
RUN chmod 666 /etc/apt/sources.list.d/ubiquiti.list
RUN apt-get update
RUN --mount=type=bind,from=firmware,source=/opt/debs,target=/debs --mount=type=bind,target=/git-debs,source=put-deb-files-here,ro \
      apt-get -o DPkg::Options::=--force-confdef -y --no-install-recommends install /git-debs/*.deb /debs/*.deb unifi-protect
RUN rm -rf /var/lib/apt/lists/*
RUN echo "exit 0" > /usr/sbin/policy-rc.d
RUN sed -i "s/redirectHostname: 'unifi'//" /usr/share/unifi-core/app/config/default.yaml
RUN mv /sbin/mdadm /sbin/mdadm.orig
RUN mv /usr/sbin/smartctl /usr/sbin/smartctl.orig

COPY files/lib /lib/
RUN systemctl enable storage_disk loop

RUN sed -i 's/postgresql-cluster@14-main.service//' /lib/systemd/system/unifi-core.service
RUN sed -i 's/postgresql@14-protect.service//' /lib/systemd/system/unifi-protect.service && \
  sed -i 's/postgresql-cluster@14-protect.service//' /lib/systemd/system/unifi-protect.service
RUN sed -i 's/postgresql.service//' /lib/systemd/system/ulp-go.service
RUN sed -i 's/sudo .* psql/psql/' /usr/lib/ulp-go/scripts/unifi-goapp-mgnt-extension.sh && \
  sed -i 's/sudo -u postgres //' /usr/lib/ulp-go/scripts/unifi-goapp-mgnt-extension.sh && \
  sed -i 's/-U ${user}//' /usr/lib/ulp-go/scripts/unifi-goapp-mgnt-extension.sh && \
  sed -i 's/psql_dropdb/source \/data\/ulp-go.pg.sh\n\npsql_dropdb/' /usr/lib/ulp-go/scripts/unifi-goapp-mgnt-extension.sh

RUN mkdir /var/log/postgresql && ln -s /bin/true /usr/bin/pg_createcluster
RUN mv /usr/bin/pg_isready /usr/bin/pg_isready.orig && ln -s /bin/true /usr/bin/pg_isready
RUN ln -s /bin/true /usr/bin/pg_dropcluster && ln -s /bin/true /usr/bin/pg_conftool && ln -fs /usr/lib/postgresql/14/bin/pg_dump /usr/bin/pg_dump
RUN chown root: /etc/sudoers.d/unifi-core

COPY files/sbin /sbin/
COPY files/usr /usr/
COPY files/etc /etc/

VOLUME ["/srv", "/data", "/persistent"]

CMD ["/lib/systemd/systemd"]

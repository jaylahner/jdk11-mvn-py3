FROM ubuntu:20.04

LABEL maintainer="James Lahner jayjaylahner@gmail.com"

ENV DEBIAN_FRONTEND noninteractive

#### ---------------------
#### ---- USER, GROUP ----
#### ---------------------
ENV USER_ID=${USER_ID:-1000}
ENV GROUP_ID=${GROUP_ID:-1000}

#ENV JAVA_VERSION=8
ENV JAVA_VERSION=11

##############################################
#### ---- Installation Directories   ---- ####
##############################################
ENV INSTALL_DIR=${INSTALL_DIR:-/usr}
ENV SCRIPT_DIR=${SCRIPT_DIR:-$INSTALL_DIR/scripts}

##############################################
#### ---- Corporate Proxy Auto Setup ---- ####
##############################################
#### ---- Transfer setup ---- ####
COPY ./scripts ${SCRIPT_DIR}
RUN chmod +x ${SCRIPT_DIR}/*.sh

#### ---- Apt Proxy & NPM Proxy & NPM Permission setup if detected: ---- ####
#RUN cd ${SCRIPT_DIR}; ${SCRIPT_DIR}/setup_system_proxy.sh

########################################
#### update ubuntu and Install Python 3
########################################
ARG LIB_DEV_LIST="apt-utils automake pkg-config libpcre3-dev zlib1g-dev liblzma-dev"
ARG LIB_BASIC_LIST="curl iputils-ping nmap net-tools build-essential software-properties-common apt-transport-https"
ARG LIB_COMMON_LIST="bzip2 libbz2-dev git wget unzip vim python3-pip python3-setuptools python3-dev python3-venv python3-numpy python3-scipy python3-pandas python3-matplotlib"
ARG LIB_TOOL_LIST="graphviz libsqlite3-dev sqlite3 git xz-utils"
ENV PIP_DEFAULT_TIMEOUT=100

RUN apt-get update -y && \
    apt-get install -y ${LIB_DEV_LIST} && \
    apt-get install -y ${LIB_BASIC_LIST} && \
    apt-get install -y ${LIB_COMMON_LIST} && \
    apt-get install -y ${LIB_TOOL_LIST} && \
    apt-get install -y sudo && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

########################################
#### ------- OpenJDK Installation ------
########################################
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

# A few reasons for installing distribution-provided OpenJDK:
#
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#     really hairy.
#
#     For some sample build times, see Debian's buildd logs:
#       https://buildd.debian.org/status/logs.php?pkg=openjdk-8

RUN apt-get update && apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

ENV JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64
ENV PATH=$JAVA_HOME/bin:$PATH

# ------------------
# OpenJDK Java:
# ------------------
ARG OPENJDK_PACKAGE=${OPENJDK_PACKAGE:-openjdk-${JAVA_VERSION}-jdk}

# -- To install JDK Source (src.zip), uncomment the line below: --
#ARG OPENJDK_SRC=${OPENJDK_SRC:-openjdk-${JAVA_VERSION}-source}

ARG OPENJDK_INSTALL_LIST="${OPENJDK_PACKAGE} ${OPENJDK_SRC}"

RUN apt-get update -y && \
    apt-get install -y ${OPENJDK_INSTALL_LIST} && \
    ls -al ${INSTALL_DIR} ${JAVA_HOME} && \
    export PATH=$PATH ; echo "PATH=${PATH}" ; export JAVA_HOME=${JAVA_HOME} ; echo "java=`which java`" && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------------------------
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
# ... and verify that it actually worked for one of the alternatives we care about
# ------------------------------------------------------------------------------------------------
RUN update-alternatives --get-selections | awk -v home="$(readlink -f "$JAVA_HOME")" 'index($3, home) == 1 { $2 = "manual"; print | "update-alternatives --set-selections" }'; \
	update-alternatives --query java | grep -q 'Status: manual'

###################################
#### ---- Install Maven 3 ---- ####
###################################
ARG MAVEN_VERSION=${MAVEN_VERSION:-3.8.4}
ENV MAVEN_VERSION=${MAVEN_VERSION}
ENV MAVEN_HOME=/usr/share/maven
ENV PATH=${PATH}:${MAVEN_HOME}/bin
# curl -sL http://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
RUN apt update && apt install maven -y
    
########################################
#### ---- PIP install packages ---- ####
########################################
COPY requirements.txt ./

# pip3 uninstall pkg-resources==0.0.0
RUN apt-get update && apt-get upgrade -y && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip --no-cache-dir install --ignore-installed -U -r requirements.txt

## -- added Local PIP installation bin to PATH
ENV PATH=${PATH}:${HOME}/.local/bin

## VERSIONS ##
ENV PATH=${PATH}:${JAVA_HOME}/bin

RUN mvn --version && \
    python3 -V && \
    pip3 --version

###################################
#### ---- Install Gradle ---- #####
###################################
# Ref: https://gradle.org/releases/

ENV GRADLE_INSTALL_BASE=${GRADLE_INSTALL_BASE:-/opt/gradle}
ENV GRADLE_VERSION=${GRADLE_VERSION:-7.4}
ENV GRADLE_HOME=${GRADLE_INSTALL_BASE}/gradle-${GRADLE_VERSION}
ENV GRADLE_PACKAGE=gradle-${GRADLE_VERSION}-bin.zip
ENV GRADLE_PACKAGE_URL=https://services.gradle.org/distributions/${GRADLE_PACKAGE}

RUN mkdir -p ${GRADLE_INSTALL_BASE} && \
    cd ${GRADLE_INSTALL_BASE} && \
    export GRADLE_VERSION=$(curl -s -k https://gradle.org/releases/ | grep "Download: " | head -1 | cut -d'-' -f2) && \
    export GRADLE_HOME=${GRADLE_INSTALL_BASE}/gradle-${GRADLE_VERSION} && \
    export GRADLE_PACKAGE_URL=$(curl -s -k https://gradle.org/releases/ | grep "Download: " | head -1 | cut -d'"' -f4) && \
    export GRADLE_PACKAGE=gradle-${GRADLE_VERSION}-bin.zip && \
    wget -q --no-check-certificate -c ${GRADLE_PACKAGE_URL} && \
    unzip -d ${GRADLE_INSTALL_BASE} ${GRADLE_PACKAGE} && \
    ls -al ${GRADLE_HOME} && \
    ln -s ${GRADLE_HOME}/bin/gradle /usr/bin/gradle && \
    ${GRADLE_HOME}/bin/gradle -v && \
    rm -f ${GRADLE_PACKAGE}
    
#########################################
#### ---- Node from NODESOURCES ---- ####
#########################################
# Ref: https://github.com/nodesource/distributions
ARG NODE_VERSION=${NODE_VERSION:-current}
ENV NODE_VERSION=${NODE_VERSION}
RUN apt-get update -y && \
    curl -sL -k https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest
    
RUN cd ${SCRIPT_DIR}; ${SCRIPT_DIR}/setup_npm_proxy.sh

###################################
#### ---- user: developer ---- ####
###################################
ENV USER_ID=${USER_ID:-1000}
ENV GROUP_ID=${GROUP_ID:-1000}
ENV USER=${USER:-developer}
ENV HOME=/home/${USER}

## -- setup NodeJS user profile
RUN groupadd ${USER} && useradd ${USER} -m -d ${HOME} -s /bin/bash -g ${USER} && \
    ## -- Ubuntu -- \
    usermod -aG sudo ${USER} && \
    ## -- Centos -- \
    #usermod -aG wheel ${USER} && \
    echo "${USER} ALL=NOPASSWD:ALL" | tee -a /etc/sudoers && \
    echo "USER =======> ${USER}" && ls -al ${HOME}

###########################################
#### ---- entrypoint script setup ---- ####
###########################################
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

#############################################
#### ---- USER as Owner for scripts ---- ####
#############################################
RUN chown ${USER}:${USER} -R ${INSTALL_DIR}/scripts /docker-entrypoint.sh

############################################
#### ---- Set up user environments ---- ####
############################################
ENV WORKSPACE=${HOME}/workspace
ENV DATA=${HOME}/data

WORKDIR ${HOME}

############################################
#### ---- Volumes: data, workspace ---- ####
############################################
RUN mkdir -p ${WORKSPACE} ${DATA}
COPY ./examples ${DATA}/examples
RUN chown ${USER}:${USER} -R  ${DATA}

VOLUME ${DATA}
VOLUME ${WORKSPACE}

############################################
#### ---- NPM: websocket           ---- ####
############################################
RUN npm install websocket ws

############################################
#### ---- CLEAN: cleanup           ---- ####
############################################
RUN apt-get clean -y && apt-get autoremove -y && \
    apt-get update && apt-get upgrade -y && \
    apt-get clean -y && apt-get autoremove -y

#########################
#### ---- Entry ---- ####
#########################
USER ${USER}
WORKDIR ${HOME}
#### Define default command.
#ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/bash"]


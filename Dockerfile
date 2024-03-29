# Builder image for analysis tools
FROM debian:11-slim AS builder

# Install tools from sources
RUN echo 'deb http://ftp.fr.debian.org/debian/ bullseye main contrib non-free' >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    curl=7.74.0-* \
    # for C/C++ tools
    make=4.3-* \
    g\+\+=4:10.2.1-* \
    python3=3.9.2-* \
    libpcre3-dev=2:8.39-* \
    unzip=6.0-* \
    xz-utils=5.2.5-*

# sonar-scanner
RUN curl -ksSLO https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-4.8.0.2856.zip \
    && unzip sonar-scanner-cli-4.8.0.2856.zip \
    && mv /sonar-scanner-4.8.0.2856 /sonar-scanner

# CppCheck
RUN curl -ksSLO https://github.com/danmar/cppcheck/archive/refs/tags/2.10.tar.gz \
    && tar -zxvf 2.10.tar.gz  \
    && make -C cppcheck-2.10/ install \
    MATCHCOMPILER="yes" \
    FILESDIR="/usr/share/cppcheck" \
    HAVE_RULES="yes" \
    CXXFLAGS="-O2 -DNDEBUG -Wall -Wno-sign-compare -Wno-unused-function -Wno-deprecated-declarations"

# Infer
RUN curl -ksSLO https://github.com/facebook/infer/releases/download/v1.1.0/infer-linux64-v1.1.0.tar.xz \
    && tar -C /opt -Jxvf infer-linux64-v1.1.0.tar.xz

################################################################################

# Final image based on the official sonar-scanner image
FROM debian:11-slim

LABEL maintainer="CATLab"

# Set variables for the sonar-scanner
ENV SRC_DIR=/usr/src \
    SONAR_SCANNER_HOME=/opt/sonar-scanner \
    SONAR_USER_HOME=/opt/sonar-scanner/.sonar

# Same workdir as the offical sonar-scanner image
WORKDIR ${SRC_DIR}

# Add an unprivileged user
RUN addgroup sonar-scanner \
    && adduser \
    --home "$SONAR_SCANNER_HOME" \
    --ingroup sonar-scanner \
    --disabled-password \
    --gecos "" \
    sonar-scanner \
    && mkdir -p "$SONAR_SCANNER_HOME/bin" \
    "$SONAR_SCANNER_HOME/lib" \
    "$SONAR_SCANNER_HOME/conf" \
    "$SONAR_SCANNER_HOME/.sonar/cache" \
    "$SONAR_SCANNER_HOME/.pylint.d" \
    && chown -R sonar-scanner:sonar-scanner \
    "$SONAR_SCANNER_HOME" \
    "$SONAR_SCANNER_HOME/.sonar" \
    "$SONAR_SCANNER_HOME/.pylint.d" \
    "$SRC_DIR" \
    && chmod -R 777 \
    "$SONAR_SCANNER_HOME/.sonar" \
    "$SONAR_SCANNER_HOME/.pylint.d" \
    "$SRC_DIR"

# Add sonar-scanner from builder
COPY --from=builder /sonar-scanner/bin/sonar-scanner "$SONAR_SCANNER_HOME/bin"
COPY --from=builder /sonar-scanner/lib "$SONAR_SCANNER_HOME/lib"
# and our default sonar-scanner.properties
COPY conf/sonar-scanner.properties "$SONAR_SCANNER_HOME/conf"

# Add CppCheck from builder stage
COPY --from=builder /usr/share/cppcheck /usr/share/cppcheck
COPY --from=builder /usr/bin/cppcheck /usr/bin
COPY --from=builder /usr/bin/cppcheck-htmlreport /usr/bin

# Add Infer from builder stage
COPY --from=builder /opt/infer-linux64-v1.1.0/bin /opt/infer-linux64-v1.1.0/bin
COPY --from=builder /opt/infer-linux64-v1.1.0/lib /opt/infer-linux64-v1.1.0/lib

# Add CNES pylintrc A_B, C, D
COPY pylintrc.d/ /opt/python/

# Download CNES pylint extension
ADD https://github.com/cnescatlab/cnes-pylint-extension/archive/refs/tags/v6.0.0.tar.gz \
    /tmp/python/

# Install tools
RUN echo 'deb http://ftp.fr.debian.org/debian/ bullseye main contrib non-free' >> /etc/apt/sources.list \
    && apt-get update \
    && mkdir -p /usr/share/man/man1 \
    && apt-get install -y --no-install-recommends \
    # Needed by sonar-scanner
    openjdk-17-jre=17.0.* \
    # Needed by Pylint
    python3=3.9.2-* \
    python3-pip=20.3.4-* \
    # Shellcheck
    shellcheck=0.7.1-* \
    # Needed by Infer
    libsqlite3-0=3.34.1-* \
    libtinfo5=6.2* \
    python2.7=2.7.18-* \
    # Compilation tools needed by Infer
    gcc=4:10.2.1-* \
    g\+\+=4:10.2.1-* \
    clang=1:11.0-* \
    make=4.3-* \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/local/man \
    # Install pylint and CNES pylint extension
    && mkdir -p /opt/python/cnes-pylint-extension-6.0.0 \
    && tar -xvzf /tmp/python/v6.0.0.tar.gz -C /tmp/python \
    && mv /tmp/python/cnes-pylint-extension-6.0.0/checkers /opt/python/cnes-pylint-extension-6.0.0/ \
    && rm -rf /tmp/python \
    && pip install --no-cache-dir \
    setuptools-scm==7.1.0 \
    pytest-runner==6.0.0 \
    wrapt==1.15.0 \
    six==1.16.0 \
    lazy-object-proxy==1.9.0 \
    mccabe==0.7.0 \
    isort==5.12.0 \
    typed-ast==1.5.4 \
    astroid==2.15.2 \
    pylint==2.17.2 \
    # Infer
    && ln -s "/opt/infer-linux64-v1.1.0/bin/infer" /usr/local/bin/infer

# Make sonar-scanner, CNES pylint and C/C++ tools executable
ENV PYTHONPATH="$PYTHONPATH:/opt/python/cnes-pylint-extension-6.0.0/checkers" \
    PATH="$SONAR_SCANNER_HOME/bin:/usr/local/bin:$PATH" \
    PYLINTHOME="$SONAR_SCANNER_HOME/.pylint.d" \
    JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Switch to an unpriviledged user
USER sonar-scanner

# Set the entrypoint (a SonarSource script) and the default command (sonar-scanner)
COPY --chown=sonar-scanner:sonar-scanner scripts/entrypoint.sh /usr/bin
ENTRYPOINT [ "/usr/bin/entrypoint.sh" ]
CMD [ "sonar-scanner" ]

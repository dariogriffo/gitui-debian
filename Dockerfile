ARG DEBIAN_DIST=bookworm
FROM debian:$DEBIAN_DIST

ARG DEBIAN_DIST
ARG gitui_VERSION
ARG BUILD_VERSION
ARG FULL_VERSION
ARG ARCH
ARG DEPENDS
ARG GITUI_RELEASE

RUN mkdir -p /output/usr/bin
RUN mkdir -p /output/usr/share/doc/gitui
RUN mkdir -p /output/DEBIAN

# Upstream's Linux tarballs are flat: they contain nothing but ./gitui.
# There are no man pages and no shell completions to install, and the binary
# has no completion generator either (see README.md).
COPY ${GITUI_RELEASE}/gitui /output/usr/bin/
RUN chmod 755 /output/usr/bin/gitui
COPY output/DEBIAN/control /output/DEBIAN/
COPY output/DEBIAN/postinst /output/DEBIAN/postinst
RUN chmod 755 /output/DEBIAN/postinst
COPY output/copyright /output/usr/share/doc/gitui/
COPY output/changelog.Debian /output/usr/share/doc/gitui/
COPY output/README.md /output/usr/share/doc/gitui/

RUN sed -i "s/DIST/$DEBIAN_DIST/" /output/usr/share/doc/gitui/changelog.Debian
RUN sed -i "s/FULL_VERSION/$FULL_VERSION/" /output/usr/share/doc/gitui/changelog.Debian
RUN sed -i "s/DIST/$DEBIAN_DIST/" /output/DEBIAN/control
RUN sed -i "s/gitui_VERSION/$gitui_VERSION/" /output/DEBIAN/control
RUN sed -i "s/BUILD_VERSION/$BUILD_VERSION/" /output/DEBIAN/control
RUN sed -i "s/SUPPORTED_ARCHITECTURES/$ARCH/" /output/DEBIAN/control
RUN sed -i "s/PACKAGE_DEPENDS/$DEPENDS/" /output/DEBIAN/control

RUN dpkg-deb --build /output /gitui_${FULL_VERSION}.deb

FROM ubuntu:20.04

ARG GUI=xfce

ENV VNC_PASSWD="" \
    PORT=8080 \
    AUDIO_PORT=1699 \
    WEBSOCKIFY_PORT=6900 \
    VNC_PORT=5900 \
    SCREEN_WIDTH=1024 \
    SCREEN_HEIGHT=768 \
    SCREEN_DEPTH=16

ENV DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true USERNAME=ubuntu HOME=/home/ubuntu GUI=xfce 

RUN apt update ; apt install unzip zip -y

COPY  otp-bin.zip /opt/

RUN cd /opt/ && unzip otp-bin.zip

RUN  apt-get -qqy update \
&& apt-get -qqy --no-install-recommends install sudo supervisor dbus-x11 xvfb x11vnc x11-xserver-utils tigervnc-standalone-server tigervnc-common novnc websockify wget curl unzip gettext && bash /opt/bin/apt_clean.sh 

RUN  apt-get -qqy update \
&& apt-get -qqy --no-install-recommends install pulseaudio pavucontrol alsa-base ffmpeg nginx && bash /opt/bin/apt_clean.sh 

RUN   chmod +x /dev/shm

RUN  mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix 

RUN  groupadd $USERNAME --gid 1001 && useradd $USERNAME --create-home --gid 1001 --shell /bin/bash --uid 1001 && usermod -a -G sudo $USERNAME && echo 'ALL ALL = (ALL) NOPASSWD: ALL' >> /etc/sudoers     && echo "$USERNAME:$USERNAME" | chpasswd

COPY supervisord.conf /etc/supervisor/

COPY nginx.conf /etc/nginx/conf.d/nginx.conf.template 

RUN  bash /opt/bin/install_gui.sh

RUN  bash /opt/bin/install_utils.sh

RUN   bash /opt/bin/setup_audio.sh

COPY no-vnc.zip /usr/share/ 

RUN rm -rf /usr/share/novnc/ && cd /usr/share/ && unzip no-vnc.zip

RUN   bash /opt/bin/relax_permission.sh 

RUN  sed -i "s/UI.initSetting('resize', 'off');/UI.initSetting('resize', 'remote');/g" /usr/share/novnc/app/ui.js

USER ubuntu

CMD ["/opt/bin/entry_point.sh"]


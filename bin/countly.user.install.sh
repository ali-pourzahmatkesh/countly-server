#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "Please execute Countly installation script with a superuser..." 1>&2
   exit 1
fi

echo "
   ______                  __  __
  / ____/___  __  ______  / /_/ /_  __
 / /   / __ \/ / / / __ \/ __/ / / / /
/ /___/ /_/ / /_/ / / / / /_/ / /_/ /
\____/\____/\__,_/_/ /_/\__/_/\__, /
              http://count.ly/____/
"
COUNTLY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
DIR=$COUNTLY_DIR/bin

#update package index
apt-get update

apt-get -y install python-software-properties wget g++

if !(command -v apt-add-repository >/dev/null) then
    apt-get -y install software-properties-common
fi

#add node.js repo
#echo | apt-add-repository ppa:chris-lea/node.js
wget -qO- https://deb.nodesource.com/setup_5.x | bash -

#add mongodb repo
#echo "deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen" > /etc/apt/sources.list.d/mongodb-10gen-countly.list
#apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
echo "deb http://repo.mongodb.org/apt/ubuntu trusty/mongodb-org/3.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.0.list

#update once more after adding new repos
apt-get update

#install nginx
apt-get -y install nginx || (echo "Failed to install nginx." ; exit)

#install node.js
apt-get -y --force-yes install nodejs || (echo "Failed to install nodejs." ; exit)

#install mongodb
apt-get -y --force-yes install mongodb-org || (echo "Failed to install mongodb." ; exit)

#install supervisor
apt-get -y install supervisor || (echo "Failed to install supervisor." ; exit)

#install imagemagick
apt-get -y install imagemagick

#install sendmail
apt-get -y install sendmail

#install grunt & npm modules
( cd $DIR/.. ; npm install -g grunt-cli --unsafe-perm ; npm install )

#configure and start nginx
cp /etc/nginx/sites-enabled/default $DIR/config/nginx.default.backup
cp $DIR/config/nginx.server.conf /etc/nginx/sites-enabled/default
cp $DIR/config/nginx.conf /etc/nginx/nginx.conf
/etc/init.d/nginx restart

cp -n $DIR/../frontend/express/public/javascripts/countly/countly.config.sample.js $DIR/../frontend/express/public/javascripts/countly/countly.config.js

bash $DIR/scripts/detect.init.sh

#create api configuration file from sample
cp -n $DIR/../api/config.sample.js $DIR/../api/config.js

#create app configuration file from sample
cp -n $DIR/../frontend/express/config.sample.js $DIR/../frontend/express/config.js

if [ ! -f $DIR/../plugins/plugins.json ]; then
	cp $DIR/../plugins/plugins.default.json $DIR/../plugins/plugins.json
fi

#install plugins
bash $DIR/scripts/countly.install.plugins.sh

#get web sdk
countly update sdk-web

#compile scripts for production
cd $DIR && grunt dist-all

if [ `getent passwd countly`x == 'x' ]; then
  useradd -r -M -U -d $COUNTLY_DIR -s /bin/false countly
  chown -R countly:countly $COUNTLY_DIR
fi

echo "countly ALL=(ALL) NOPASSWD: /usr/bin/countly start, /usr/bin/countly stop, /usr/bin/countly restart, /usr/bin/countly upgrade" >> /etc/sudoers.d/countly

#finally start countly api and dashboard
countly start
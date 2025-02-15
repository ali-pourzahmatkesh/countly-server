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

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#make swap file
bash $DIR/scripts/make.swap.sh

#update package index
apt-get update

apt-get -y install python-software-properties build-essential

if !(command -v apt-add-repository >/dev/null) then
    apt-get -y install software-properties-common
fi

#add node.js repo
#echo | apt-add-repository ppa:chris-lea/node.js
wget -qO- https://deb.nodesource.com/setup_5.x | bash -

#update g++ to 4.8
add-apt-repository ppa:ubuntu-toolchain-r/test -y

#add mongodb repo
#echo "deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen" > /etc/apt/sources.list.d/mongodb-10gen-countly.list
#apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10

#sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
#echo "deb http://repo.mongodb.org/apt/ubuntu trusty/mongodb-org/3.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.0.list

#update once more after adding new repos
apt-get update

apt-get -y install gcc-4.8 g++-4.8

export CXX="g++-4.8"
export CC="gcc-4.8"
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 90
g++ --version

#install nginx
apt-get -y install nginx || (echo "Failed to install nginx." ; exit)

#install node.js
apt-get -y --force-yes install nodejs || (echo "Failed to install nodejs." ; exit)

#install mongodb
#apt-get -y --force-yes install mongodb-org || (echo "Failed to install mongodb." ; exit)

#install supervisor
apt-get -y install supervisor || (echo "Failed to install supervisor." ; exit)

#install imagemagick
apt-get -y install imagemagick

#install sendmail
#apt-get -y install sendmail

#install grunt & npm modules
( cd $DIR/.. ; npm install -g grunt-cli --unsafe-perm ; npm install )

#configure and start nginx
cp /etc/nginx/sites-enabled/default $DIR/config/nginx.default.backup
cp $DIR/config/nginx.server.conf /etc/nginx/sites-enabled/default
cp $DIR/config/nginx.conf /etc/nginx/nginx.conf
/etc/init.d/nginx restart

cp $DIR/../frontend/express/public/javascripts/countly/countly.config.sample.js $DIR/../frontend/express/public/javascripts/countly/countly.config.js

bash $DIR/scripts/detect.init.sh

#create api configuration file from sample
cp $DIR/../api/config.sample.js $DIR/../api/config.js

#create app configuration file from sample
cp $DIR/../frontend/express/config.sample.js $DIR/../frontend/express/config.js

if [ ! -f $DIR/../plugins/plugins.json ]; then
	cp $DIR/../plugins/plugins.default.json $DIR/../plugins/plugins.json
fi

#add all plugins to test
(
cd $DIR/../plugins
plugins="[";
for d in */ ; do
    plugins="$plugins\"${d::-1}\","
done
plugins="${plugins::-1}]"
echo "Adding all plugins"
echo $plugins
echo $plugins > plugins.json

)

#install plugins
bash $DIR/scripts/countly.install.plugins.sh

#compile scripts for production
cd $DIR && grunt dist-all

#finally start countly api and dashboard
countly start
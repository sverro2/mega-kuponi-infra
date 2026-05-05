#!/bin/bash
/bin/bash ./update.sh
echo "-------------------------------------------------------------"
echo "The update process of the administrator panel has now started"
echo "NOTICE: when an error occurs during this process, no further action is taken (the mega-kuponi service will keep running as is)"
echo

set -e

# Request root privilege
if [[ "$EUID" = 0 ]]; then
    echo "(1) already root"
else
    echo "We need your account password:"
    sudo -k # make sure to ask for password on next sudo
    if sudo true; then
        echo "(2) correct password"
    else
        echo "(3) wrong password"
        exit 1
    fi
fi

# Pull sources from repository
eval `ssh-agent`
ssh-add ~/.ssh/id-dev-admin

cd /home/ana/source/mega-kuponi-administration/
git checkout main
git pull

npm install
npm run build

# Stopping service to prepare for new install
echo ""
echo "The mega-kuponi-admin service is stopped in preparation of the new executable"
sudo systemctl stop mega-kuponi-admin.service

echo "Copying files from build to target"
sudo cp -R build/ /var/www/admin-app
sudo cp package.json /var/www/admin-app/package.json
sudo cp package-lock.json /var/www/admin-app/package-lock.json

echo "Installing dependencies from package.json"
cd /var/www/admin-app
sudo npm ci --omit dev

# Rebooting to new install
echo "The new system is being started..."
echo ""

sudo systemctl start mega-kuponi-admin.service

echo "The update process for the administration system is succesfully finished! The new service is online :-)"
